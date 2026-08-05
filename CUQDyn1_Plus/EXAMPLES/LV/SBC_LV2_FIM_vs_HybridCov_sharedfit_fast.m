%% SBC_LV2_FIM_vs_HybridCov_sharedfit_fast.m
% Calibration experiment comparing FIM and HybridCov UQ on the same fitted
% LV replicate.
%
% IMPORTANT DIFFERENCE FROM SBC_LV2_FIM_vs_HybridCov.m
% ----------------------------------------------------
% Each synthetic dataset is fitted once with CUQDyn1_Plus_HybridCov. The
% HybridCov result already contains both covariance matrices:
%   results.Cov_p_fim  - FIM covariance from the shared fit
%   results.Cov_p      - Hybrid covariance D_FIM * R_LOO * D_FIM
% This script recomputes FIM trajectory bands from results.Cov_p_fim, so
% FIM and HybridCov are compared on the exact same optimizer solution,
% LOO ensemble, residual variance, and sensitivity linearization.
%
% Set sample_true_parameters=true for prior-predictive SBC. The default
% false setting is a conditional coverage experiment at nominal LV truth.
%

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% ====================================================================
% USER CONTROL PANEL
% ====================================================================
config = default_sharedfit_config();
n_sim             = config.n_sim;
noise_pct         = config.noise_pct;
alp               = config.alp;
rng_seed          = config.rng_seed;
calibration_mode  = config.calibration_mode;
data_noise_model  = config.data_noise_model;
rep_result_mode   = config.rep_result_mode;

sample_true_parameters = strcmpi(calibration_mode, 'prior_predictive');
clip_negative_data     = strcmpi(data_noise_model, 'clipped_gaussian');
save_rep_results       = strcmpi(rep_result_mode, 'keep');

% --- LV problem ---
dynamics_handle      = @prob_mod_dynamics_LV;
cost_handle          = @prob_mod_cost_LV;
nstates              = 2;
n_params             = 4;
param_names          = {'alpha','beta','delta','gamma'};
nominal_parameters   = [0.5, 0.02, 0.02, 0.5];
initial_conditions   = [10, 5];
time_points          = (0.0 : 1.0 : 30.0)';
is_observed          = [true, false];

lb_params    = nominal_parameters * 0.2;
ub_params    = nominal_parameters * 2.0;
guess_params = nominal_parameters * 0.8;

unobs_idx = find(~is_observed);

opts = cuqdyn_default_options(n_params, 'sbc');
opts.uq.alp = alp;
opts.ode.RelTol = 1e-9;
opts.ode.AbsTol = 1e-11;
opts.meigo.refit.strategy = 'local_after_global';
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;
% For quick debugging, override for example:
% meigo_opts.maxeval = n_params * 250;

% ====================================================================
% DERIVED QUANTITIES
% ====================================================================
m                = numel(time_points);
n_eval           = m - 1;
nominal_coverage = 1 - 2*alp;
options_ode      = cuqdyn_get_ode_options();

% ====================================================================
% DIRECTORIES AND LOGGING
% ====================================================================
nowTime   = datetime('now');
timestamp = string(nowTime,'yyyy-MM-dd_HH-mm-ss');
sbcDir    = "SBC_Results_LV2_FIM_vs_HybridCov_sharedfit_fast_" + timestamp;
mkdir(sbcDir);

tmpDir = fullfile(sbcDir, 'tmp_data');
mkdir(tmpDir);

logFile = fullfile(sbcDir,'sbc_log.txt');
fid0 = fopen(logFile,'w'); fclose(fid0);
PRINT = @(varargin) dual_print(logFile, varargin{:});

PRINT('SBC FIM vs HybridCov shared-fit comparison --- %s\n', timestamp);
PRINT('n_sim=%d  noise=%.0f%%  alp=%.4f  nominal=%.1f%%\n', ...
      n_sim, noise_pct, alp, nominal_coverage*100);
PRINT('calibration_mode=%s  data_noise_model=%s  rep_result_mode=%s\n\n', ...
      calibration_mode, data_noise_model, rep_result_mode);

% ====================================================================
% STORAGE
% ====================================================================
covered_fim = NaN(n_sim, n_eval);
covered_hyb = NaN(n_sim, n_eval);
width_fim   = NaN(n_sim, n_eval);
width_hyb   = NaN(n_sim, n_eval);

success     = false(n_sim, 1);
params_fit  = NaN(n_sim, n_params);
params_true = NaN(n_sim, n_params);
D_fim_all   = NaN(n_sim, n_params);
D_hyb_all   = NaN(n_sim, n_params);

% ====================================================================
% MAIN LOOP
% ====================================================================
rng(rng_seed);
PRINT('=== Starting shared-fit calibration: %d replicates ===\n\n', n_sim);
t_loop_start = tic;

for s = 1:n_sim
    PRINT('%s\n', repmat('=',1,64));
    PRINT('REPLICATE %d / %d\n', s, n_sim);
    PRINT('%s\n', repmat('=',1,64));
    t_rep = tic;

    if sample_true_parameters
        true_parameters = sample_log_uniform(lb_params, ub_params);
    else
        true_parameters = nominal_parameters;
    end
    params_true(s,:) = true_parameters;

    [~, Y_true] = ode15s(@(t,y) dynamics_handle(t,y,true_parameters), ...
                         time_points, initial_conditions, options_ode);
    sigma = observation_sigma(Y_true, is_observed, noise_pct);
    meigo_opts_rep = meigo_opts;
    meigo_opts_rep.cost_opts = opts.cost;
    meigo_opts_rep.cost_opts.residual_model = 'known_sigma';
    meigo_opts_rep.cost_opts.sigma = sigma(is_observed);
    meigo_opts_rep.cost_opts.sigma_is_known = true;

    Y_noisy = Y_true;
    for j = 1:nstates
        if is_observed(j)
            Y_noisy(2:end,j) = Y_true(2:end,j) + sigma(j)*randn(m-1,1);
            if clip_negative_data
                Y_noisy(Y_noisy(:,j)<0,j) = 0;
            end
        else
            Y_noisy(2:end,j) = NaN;
        end
    end

    data_matrix = [time_points, Y_noisy];
    tmpName = sprintf('lv_sbc_sharedfit_rep%03d.csv', s);
    tmpCsv = fullfile(tmpDir, tmpName);
    hdrs = [{'time'}, arrayfun(@(j) sprintf('y%d',j), 1:nstates, 'UniformOutput', false)];
    writetable(array2table(data_matrix, 'VariableNames', hdrs), tmpCsv);

    [times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep] = ...
        loadStateData(tmpDir, tmpName, nstates);

    repDir = fullfile(sbcDir, sprintf('rep%03d_sharedfit', s));
    mkdir(repDir);

    try
        res_hyb = CUQDyn1_Plus_HybridCov( ...
            cost_handle, dynamics_handle, nstates, n_params, ...
            guess_params, lb_params, ub_params, alp, ...
            times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep, ...
            repDir, meigo_opts_rep);

        [UQ_lower_fim, UQ_upper_fim, std_y_fim] = gaussian_bands_from_cov( ...
            res_hyb.media_tot, res_hyb.Cov_p_fim, res_hyb.parameters_init, ...
            ic_rep, times_rep, dynamics_handle, alp);

        params_fit(s,:) = res_hyb.parameters_init;
        D_fim_all(s,:)  = sqrt(diag(res_hyb.Cov_p_fim))';
        D_hyb_all(s,:)  = sqrt(diag(res_hyb.Cov_p))';
        success(s)      = true;

        for j = unobs_idx
            lo_fim = UQ_lower_fim(2:end,j);
            hi_fim = UQ_upper_fim(2:end,j);
            lo_hyb = res_hyb.UQ_lower(2:end,j);
            hi_hyb = res_hyb.UQ_upper(2:end,j);

            covered_fim(s,:) = (Y_true(2:end,j) >= lo_fim) & (Y_true(2:end,j) <= hi_fim);
            covered_hyb(s,:) = (Y_true(2:end,j) >= lo_hyb) & (Y_true(2:end,j) <= hi_hyb);
            width_fim(s,:)   = hi_fim - lo_fim;
            width_hyb(s,:)   = hi_hyb - lo_hyb;
        end

        if save_rep_results
            save(fullfile(repDir, 'sharedfit_comparison.mat'), ...
                'res_hyb', 'UQ_lower_fim', 'UQ_upper_fim', 'std_y_fim', ...
                'Y_true', 'Y_noisy', 'true_parameters');
        else
            delete(fullfile(repDir, 'CUQDyn1_Plus_HybridCov_results.mat'));
        end

        PRINT('  coverage FIM=%.1f%%  HYB=%.1f%%\n', ...
            mean(covered_fim(s,:), 'omitnan')*100, ...
            mean(covered_hyb(s,:), 'omitnan')*100);
        PRINT('  width    FIM=%.3f  HYB=%.3f\n', ...
            mean(width_fim(s,:), 'omitnan'), ...
            mean(width_hyb(s,:), 'omitnan'));

    catch ME
        PRINT('  FAILED: %s\n', ME.message);
    end

    PRINT('  Replicate %d done in %.1f s\n\n', s, toc(t_rep));
end

PRINT('\nTotal calibration time: %.1f min\n', toc(t_loop_start)/60);

% ====================================================================
% SUMMARY STATISTICS
% ====================================================================
idx_success = success;
n_success   = sum(idx_success);

if n_success == 0
    error('SBC_LV2_sharedfit:NoSuccessfulReplicates', ...
        'No successful replicates; inspect %s for failure messages.', logFile);
end

ptwise_fim = mean(covered_fim(idx_success,:), 2, 'omitnan');
ptwise_hyb = mean(covered_hyb(idx_success,:), 2, 'omitnan');

simult_fim = all(covered_fim(idx_success,:), 2);
simult_hyb = all(covered_hyb(idx_success,:), 2);

pt_by_time_fim = mean(covered_fim(idx_success,:), 1, 'omitnan');
pt_by_time_hyb = mean(covered_hyb(idx_success,:), 1, 'omitnan');

fprintf('\n%s\n Shared-fit calibration: FIM vs HybridCov — Lotka-Volterra\n%s\n', ...
        repmat('=',1,70), repmat('=',1,70));
fprintf('Nominal coverage: %.1f%%\n', nominal_coverage*100);
fprintf('Successful replicates: %d / %d\n\n', n_success, n_sim);

for method = {'FIM','HYB'}
    name = method{1};
    switch name
        case 'FIM'
            ptw = ptwise_fim; sim = simult_fim;
            wid = width_fim(idx_success,:); D_m = D_fim_all(idx_success,:);
        case 'HYB'
            ptw = ptwise_hyb; sim = simult_hyb;
            wid = width_hyb(idx_success,:); D_m = D_hyb_all(idx_success,:);
    end
    fprintf('--- %s ---\n', name);
    fprintf('  Mean pointwise coverage:    %.1f%%\n', mean(ptw,'omitnan')*100);
    fprintf('  Std  pointwise coverage:    %.1f%%\n', std(ptw,'omitnan')*100);
    fprintf('  Simultaneous coverage:      %.1f%%\n', mean(sim)*100);
    fprintf('  Mean band width (predator): %.4f\n', mean(wid(:),'omitnan'));
    fprintf('  Mean marginal std devs:     %s\n\n', num2str(mean(D_m,1,'omitnan'),'%.4g '));
end

% ====================================================================
% FIGURES
% ====================================================================
t_eval = time_points(2:end);

fig1 = figure('Color','w','Position',[50 50 900 400]);
hold on; grid on;
plot(t_eval, pt_by_time_fim*100, 'r-s', 'LineWidth', 2, 'MarkerSize', 5, 'DisplayName', 'FIM');
plot(t_eval, pt_by_time_hyb*100, 'g-^', 'LineWidth', 2, 'MarkerSize', 5, 'DisplayName', 'Hybrid');
yline(nominal_coverage*100, 'k--', 'LineWidth', 2, ...
      'DisplayName', sprintf('Nominal %.0f%%', nominal_coverage*100));
ylim([0 105]); xlabel('Time'); ylabel('Coverage (%)');
title(sprintf('Shared-fit pointwise coverage — predator [successful n=%d]', n_success));
legend('Location','south');
savefig_png(fig1, fullfile(sbcDir,'fig1_coverage_by_time'));

fig2 = figure('Color','w','Position',[100 100 700 400]);
hold on; grid on;
histogram(ptwise_fim*100, 'BinWidth', 5, 'FaceColor', 'r', 'FaceAlpha', 0.5, 'DisplayName', 'FIM');
histogram(ptwise_hyb*100, 'BinWidth', 5, 'FaceColor', 'g', 'FaceAlpha', 0.5, 'DisplayName', 'Hybrid');
xline(nominal_coverage*100, 'k--', 'LineWidth', 2);
xlabel('Pointwise coverage per successful replicate (%)'); ylabel('Count');
title('Shared-fit per-replicate coverage distribution');
legend;
savefig_png(fig2, fullfile(sbcDir,'fig2_coverage_dist'));

fig3 = figure('Color','w','Position',[150 150 900 400]);
hold on; grid on;
plot(t_eval, mean(width_fim(idx_success,:),1,'omitnan'), 'r-s', ...
     'LineWidth', 2, 'MarkerSize', 5, 'DisplayName', 'FIM');
plot(t_eval, mean(width_hyb(idx_success,:),1,'omitnan'), 'g-^', ...
     'LineWidth', 2, 'MarkerSize', 5, 'DisplayName', 'Hybrid');
xlabel('Time'); ylabel('Mean band width');
title('Shared-fit mean prediction band width — predator');
legend('Location','best');
savefig_png(fig3, fullfile(sbcDir,'fig3_band_width'));

fig4 = figure('Color','w','Position',[200 200 1000 600]);
for p = 1:n_params
    subplot(2,2,p); hold on; grid on;
    histogram(D_fim_all(idx_success,p), 'FaceColor', 'r', 'FaceAlpha', 0.5, 'DisplayName', 'FIM');
    histogram(D_hyb_all(idx_success,p), 'FaceColor', 'g', 'FaceAlpha', 0.5, 'DisplayName', 'Hybrid');
    xlabel('Marginal std dev'); ylabel('Count');
    title(param_names{p});
    if p == 1, legend; end
end
sgtitle('Shared-fit marginal parameter std devs');
savefig_png(fig4, fullfile(sbcDir,'fig4_marginal_stdev'));

fig5 = figure('Color','w','Position',[250 250 600 500]);
methods = {'FIM','Hybrid'};
cov_means = [mean(ptwise_fim,'omitnan'), mean(ptwise_hyb,'omitnan')] * 100;
cov_stds  = [std(ptwise_fim,'omitnan'), std(ptwise_hyb,'omitnan')] * 100;
width_means = [mean(width_fim(idx_success,:), 'all', 'omitnan'), ...
               mean(width_hyb(idx_success,:), 'all', 'omitnan')];

subplot(2,1,1); hold on; grid on;
hb = bar(1:2, cov_means, 'FaceColor', 'flat');
hb.CData = [0.9 0.2 0.2; 0.1 0.7 0.3];
errorbar(1:2, cov_means, cov_stds, 'k.', 'LineWidth', 1.5);
yline(nominal_coverage*100, 'k--', 'LineWidth', 2);
set(gca, 'XTick', 1:2, 'XTickLabel', methods);
ylabel('Mean ptwise coverage (%)');
title('Shared-fit coverage calibration summary');
ylim([0 105]);

subplot(2,1,2); hold on; grid on;
hb2 = bar(1:2, width_means, 'FaceColor', 'flat');
hb2.CData = [0.9 0.2 0.2; 0.1 0.7 0.3];
set(gca, 'XTick', 1:2, 'XTickLabel', methods);
ylabel('Mean band width (predator)');
title('Shared-fit mean prediction band width');

sgtitle('Shared-fit SBC comparison — Lotka-Volterra');
savefig_png(fig5, fullfile(sbcDir,'fig5_summary'));

% ====================================================================
% SAVE WORKSPACE
% ====================================================================
save(fullfile(sbcDir,'SBC_sharedfit_workspace.mat'), ...
     'covered_fim','covered_hyb','width_fim','width_hyb', ...
     'ptwise_fim','ptwise_hyb','simult_fim','simult_hyb', ...
     'pt_by_time_fim','pt_by_time_hyb','success','n_success', ...
     'D_fim_all','D_hyb_all','params_fit','params_true', ...
     'nominal_parameters','nominal_coverage','n_sim','alp','noise_pct', ...
     'calibration_mode','data_noise_model','rep_result_mode','time_points', ...
     'param_names','lb_params','ub_params','guess_params');

fprintf('All results saved to  %s\n', sbcDir);
fprintf('Log written to        %s\n', logFile);

% ====================================================================
% LOCAL FUNCTIONS
% ====================================================================
function config = default_sharedfit_config()
    config = struct();
    config.n_sim = 50;
    config.noise_pct = 10.0;
    config.alp = 0.025;
    config.rng_seed = 42;
    config.calibration_mode = 'conditional';   % 'conditional' or 'prior_predictive'
    config.data_noise_model = 'gaussian';      % 'gaussian' or 'clipped_gaussian'
    config.rep_result_mode = 'discard';        % 'discard' or 'keep'
end

function p = sample_log_uniform(lb, ub)
    p = exp(log(lb) + rand(size(lb)) .* (log(ub) - log(lb)));
end

function sigma = observation_sigma(Y_true, is_observed, noise_pct)
    sigma = zeros(1, size(Y_true, 2));
    for jj = 1:size(Y_true, 2)
        if is_observed(jj)
            scale = mean(abs(Y_true(:,jj)));
            if scale < 1e-10
                scale = 1e-3;
            end
            sigma(jj) = (noise_pct / 100) * scale;
        end
    end
end

function [UQ_lower, UQ_upper, std_y] = gaussian_bands_from_cov( ...
        media_tot, Cov_p, parameters_init, initial_values, times, dynamics_handle, alp)
    [m, nstates] = size(media_tot);
    n_params = numel(parameters_init);
    S = zeros(m, nstates, n_params);
    h = 1e-20;

    for kk = 1:n_params
        p_complex = parameters_init;
        p_complex(kk) = p_complex(kk) + 1i*h;
        sol = ODE_solve(initial_values, times, p_complex, dynamics_handle);
        S(:,:,kk) = imag(sol(:,2:end)) / h;
    end

    Var_y = zeros(m, nstates);
    for tt = 1:m
        St = squeeze(S(tt,:,:));
        if nstates == 1
            St = St(:)';
        end
        Var_y(tt,:) = diag(St * Cov_p * St.');
    end

    std_y = sqrt(max(Var_y, 0));
    z = norminv(1 - alp);
    UQ_lower = media_tot - z * std_y;
    UQ_upper = media_tot + z * std_y;
    UQ_lower(1,:) = initial_values;
    UQ_upper(1,:) = initial_values;
end

function dual_print(logpath, varargin)
    str = sprintf(varargin{:});
    fprintf('%s', str);
    fid = fopen(logpath,'a');
    if fid > 0
        fprintf(fid,'%s',str);
        fclose(fid);
    end
end
