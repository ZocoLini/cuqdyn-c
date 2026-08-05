%% SBC_AP_FIM_vs_HybridCov_fast.m
%
% Simulation-Based Calibration for the alpha-pinene isomerization (AP)
% partial observability example, comparing the two most competitive methods:
%
%   FIM     CUQDyn1_Plus:           Cov_p solves (J'J + eps*I) Cov_p = sigma2 I
%   HYB     CUQDyn1_Plus_HybridCov: Cov_p = D_FIM * R_LOO * D_FIM
%
% PROBLEM SETUP
% -------------
%   5 states, 5 parameters
%   States 1-4 observed;  state 5 unobserved after t=0
%   alp = 0.05  =>  nominal 1-2*alp = 90% coverage
%   Time points and initial conditions taken from the experimental data
%   file (same grid used in the real run script)
%
% NOISE MODEL
% -----------
%   Proportional Gaussian noise added independently to each observed state:
%       sigma_k = (noise_pct/100) * mean(x_k*(t))
%   Noise is applied at t_2,...,t_n only; initial conditions are known.
%
% Both methods run on identical synthetic datasets (same RNG seed, same
% noise draws) so all coverage differences are attributable to the method.
%
% OUTPUT
%   sbcDir/  — timestamped directory containing:
%     fig1_coverage_by_time.png     pointwise coverage vs time (both methods)
%     fig2_coverage_dist.png        per-replicate coverage histograms
%     fig3_band_width.png           mean band width vs time
%     fig4_param_recovery.png       full-data parameter estimate distributions
%     fig5_marginal_stddev.png      FIM vs Hybrid marginal std devs
%     fig6_loo_correlation.png      LOO correlation matrix (last replicate)
%     fig7_summary.png              calibration summary bar chart
%     SBC_AP_workspace.mat          full workspace for post-hoc analysis
%     sbc_log.txt                   per-replicate verbose log
%

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% ====================================================================
% USER CONTROL PANEL
% ====================================================================
n_sim          = 50;
noise_pct      = 10.0;   % % proportional noise on each observed state
rng_seed       = 42;
bound_tol_frac = 0.02;   % bound proximity threshold for optimizer diagnostics

% --- AP problem definition (must match run_AP script exactly) ---
dynamics_handle = @prob_mod_dynamics_AP;
cost_handle     = @prob_mod_cost_AP;
nstates         = 5;
n_params        = 5;
param_names     = {'k1','k2','k3','k4','k5'};
true_parameters = [5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05];
lb_params       = true_parameters * 0.2;
ub_params       = true_parameters * 2.0;
guess_params    = true_parameters * 0.8;
alp             = 0.05;   % 90% nominal two-sided coverage

% Observability pattern: states 1-4 observed, state 5 unobserved
is_observed = [1, 1, 1, 1, 0];
unobs_idx   = find(~is_observed);   % = 5

% Reference data file (used only to extract time grid and initial conditions)
dataDir        = fullfile(fileparts(mfilename('fullpath')), 'data');
data_file_name = 'AP_measurementData_1_4.csv';

% ====================================================================
% DERIVED QUANTITIES
% ====================================================================
nominal_coverage = 1 - 2*alp;
bound_range      = ub_params - lb_params;
n_obs_states     = sum(is_observed);   % 4

% Optimiser / integration defaults for calibration runs.
opts = cuqdyn_default_options(n_params, 'sbc');
opts.uq.alp = alp;
opts.ode.RelTol = 1e-9;
opts.ode.AbsTol = 1e-11;
opts.meigo.maxeval = n_params * 1000;
opts.meigo.refit.strategy = 'local_after_global';
opts.meigo.parallel.use_parallel = false;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

% ====================================================================
% LOAD REFERENCE TIME GRID AND INITIAL CONDITIONS
% ====================================================================
% We use loadStateData on the real measurement file to obtain the
% experimental time vector and initial conditions.  Synthetic noise
% will be added to the true trajectory evaluated at these same times.
[times_ref, ~, ic_ref, ~, obs_idx_ref] = ...
    loadStateData(dataDir, data_file_name, nstates);

m     = length(times_ref);    % number of time points (including t=0)
n_eval = m - 1;               % evaluation points (excluding t=0)
n_loo_folds = m - 1;

% ====================================================================
% TRUE TRAJECTORY AT REFERENCE TIME POINTS
% ====================================================================
options_ode = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t,y) dynamics_handle(t,y,true_parameters), ...
                     times_ref, ic_ref, options_ode);

% Per-state proportional noise standard deviations (observed states only)
sigma = zeros(1, nstates);
for j = 1:nstates
    if is_observed(j)
        mv = mean(Y_true(:,j));
        sigma(j) = (mv < 1e-10)*1e-3 + (mv >= 1e-10)*(noise_pct/100)*mv;
    end
end
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = sigma(is_observed == 1);
opts.cost.sigma_is_known = true;
meigo_opts.cost_opts = opts.cost;

fprintf('AP SBC setup:\n');
fprintf('  Time points: %d  (t0=%.1f to tf=%.1f)\n', m, times_ref(1), times_ref(end));
fprintf('  Observed states: %s\n', num2str(find(is_observed)));
fprintf('  Unobserved states: %d\n', unobs_idx);
fprintf('  Noise sigma per observed state: %s\n', num2str(sigma(is_observed==1),'%.4g '));
fprintf('  Nominal coverage: %.0f%%\n\n', nominal_coverage*100);

% ====================================================================
% DIRECTORIES AND LOG
% ====================================================================
tmpDir = 'SBC_AP_tmp_data';
if ~exist(tmpDir,'dir'), mkdir(tmpDir); end

nowTime   = datetime('now');
timestamp = string(nowTime,'yyyy-MM-dd_HH-mm-ss');
sbcDir    = "SBC_Results_AP_FIM_vs_HybridCov_fast_" + timestamp;
mkdir(sbcDir);

logFile = fullfile(sbcDir,'sbc_log.txt');
fid0 = fopen(logFile,'w'); fclose(fid0);
PRINT = @(varargin) dual_print(logFile, varargin{:});

PRINT('SBC: AP FIM vs HybridCov  ---  %s\n', timestamp);
PRINT('n_sim=%d  noise=%.0f%%  alp=%.4f  nominal_cov=%.0f%%\n\n', ...
      n_sim, noise_pct, alp, nominal_coverage*100);

% ====================================================================
% STORAGE ARRAYS
% ====================================================================
% Coverage and band width for the single unobserved state (state 5).
% Rows = replicates, columns = time points t_2 ... t_n.
covered_fim = NaN(n_sim, n_eval);
covered_hyb = NaN(n_sim, n_eval);
width_fim   = NaN(n_sim, n_eval);
width_hyb   = NaN(n_sim, n_eval);

% Full-data parameter estimates per replicate
params_fim = NaN(n_sim, n_params);
params_hyb = NaN(n_sim, n_params);

% Covariance diagnostics
D_fim_all = NaN(n_sim, n_params);   % FIM marginal std devs
D_hyb_all = NaN(n_sim, n_params);   % Hybrid marginal std devs (= D_fim by construction)
D_loo_all = NaN(n_sim, n_params);   % LOO marginal std devs (from Hybrid run)

% LOO optimizer diagnostics (extracted from Hybrid run, which runs the
% same LOO loop as CUQDyn1_Plus_LOO)
all_loo_params    = NaN(n_sim, n_loo_folds, n_params);
loo_any_bound_hit = false(n_sim, n_loo_folds);

% Last replicate LOO correlation matrix (for Fig 6)
R_loo_last = NaN(n_params, n_params);

% ====================================================================
% MAIN SBC LOOP
% ====================================================================
rng(rng_seed);
PRINT('=== Starting SBC: %d replicates ===\n\n', n_sim);
t_loop_start = tic;

for s = 1:n_sim

    PRINT('%s\n', repmat('=',1,60));
    PRINT('REPLICATE %d / %d\n', s, n_sim);
    PRINT('%s\n', repmat('=',1,60));
    t_rep = tic;

    % ------------------------------------------------------------------
    % STEP 1: Generate synthetic dataset
    % ------------------------------------------------------------------
    Y_noisy = Y_true;
    for j = 1:nstates
        if is_observed(j)
            noise_j = sigma(j) * randn(m-1, 1);
            Y_noisy(2:end, j) = Y_true(2:end, j) + noise_j;
            Y_noisy(Y_noisy(:,j) < 0, j) = 0;   % physical lower bound
        end
    end

    % Build data matrix: [time, y1, y2, y3, y4, y5]
    % Unobserved state (5) set to NaN after t=0
    data_matrix = [times_ref(:), Y_noisy];
    for j = unobs_idx
        data_matrix(2:end, j+1) = NaN;
    end

    tmp_csv = fullfile(tmpDir, sprintf('ap_sbc_rep%03d.csv', s));
    hdrs    = [{'time'}, arrayfun(@(j) sprintf('y%d',j), 1:nstates, 'UniformOutput', false)];
    writetable(array2table(data_matrix, 'VariableNames', hdrs), tmp_csv);

    [times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep] = ...
        loadStateData(tmpDir, sprintf('ap_sbc_rep%03d.csv',s), nstates);

    % ------------------------------------------------------------------
    % STEP 2: FIM  (CUQDyn1_Plus)
    % ------------------------------------------------------------------
    repDir_fim = fullfile(sbcDir, sprintf('rep%03d_FIM', s));
    mkdir(repDir_fim);
    try
        res_fim = CUQDyn1_Plus( ...
            cost_handle, dynamics_handle, nstates, n_params, ...
            guess_params, lb_params, ub_params, alp, ...
            times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep, ...
            repDir_fim, meigo_opts);

        params_fim(s,:) = res_fim.parameters_init;
        D_fim_all(s,:)  = sqrt(diag(res_fim.Cov_p))';

        % Record coverage and width for each unobserved state
        for j = unobs_idx
            lo = res_fim.UQ_lower(2:end, j);
            hi = res_fim.UQ_upper(2:end, j);
            covered_fim(s,:) = (Y_true(2:end,j) >= lo) & (Y_true(2:end,j) <= hi);
            width_fim(s,:)   = hi - lo;
        end

        J_fim = sum((obs_data_rep - res_fim.media_tot(:,obs_idx_rep)).^2, 'all');
        PRINT('  [FIM] J=%.6f  coverage=%.1f%%  mean_width=%.4f\n', ...
              J_fim, mean(covered_fim(s,:),'omitnan')*100, ...
              mean(width_fim(s,:),'omitnan'));

        % Per-parameter relative errors vs true values
        PRINT('  [FIM] RelErr%%: ');
        for p = 1:n_params
            PRINT('%s=%.1f%% ', param_names{p}, ...
                  100*abs(res_fim.parameters_init(p)-true_parameters(p))/true_parameters(p));
        end
        PRINT('\n');

    catch ME
        PRINT('  [FIM] FAILED: %s\n%s\n', ME.message, getReport(ME,'extended'));
    end

    % ------------------------------------------------------------------
    % STEP 3: HYBRID  (CUQDyn1_Plus_HybridCov)
    % ------------------------------------------------------------------
    repDir_hyb = fullfile(sbcDir, sprintf('rep%03d_HYB', s));
    mkdir(repDir_hyb);
    try
        res_hyb = CUQDyn1_Plus_HybridCov( ...
            cost_handle, dynamics_handle, nstates, n_params, ...
            guess_params, lb_params, ub_params, alp, ...
            times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep, ...
            repDir_hyb, meigo_opts);

        params_hyb(s,:) = res_hyb.parameters_init;
        D_hyb_all(s,:)  = sqrt(diag(res_hyb.Cov_p))';
        D_loo_all(s,:)  = sqrt(diag(res_hyb.Cov_p_loo))';

        % LOO optimizer diagnostics
        lp      = res_hyb.loo_params;   % [(m-1) x n_params]
        n_folds = size(lp, 1);
        all_loo_params(s, 1:n_folds, :) = lp;
        for f = 1:n_folds
            near_lb = (lp(f,:) - lb_params) ./ bound_range < bound_tol_frac;
            near_ub = (ub_params - lp(f,:)) ./ bound_range < bound_tol_frac;
            loo_any_bound_hit(s,f) = any(near_lb | near_ub);
        end

        % Coverage and width for unobserved state
        for j = unobs_idx
            lo = res_hyb.UQ_lower(2:end, j);
            hi = res_hyb.UQ_upper(2:end, j);
            covered_hyb(s,:) = (Y_true(2:end,j) >= lo) & (Y_true(2:end,j) <= hi);
            width_hyb(s,:)   = hi - lo;
        end

        J_hyb = sum((obs_data_rep - res_hyb.media_tot(:,obs_idx_rep)).^2, 'all');
        PRINT('  [HYB] J=%.6f  coverage=%.1f%%  mean_width=%.4f\n', ...
              J_hyb, mean(covered_hyb(s,:),'omitnan')*100, ...
              mean(width_hyb(s,:),'omitnan'));
        PRINT('  [HYB] LOO bound-hit rate this rep: %.1f%%\n', ...
              mean(loo_any_bound_hit(s,1:n_folds))*100);

        % Save last replicate's R_loo for Fig 6
        R_loo_last = res_hyb.R_loo;

    catch ME
        PRINT('  [HYB] FAILED: %s\n%s\n', ME.message, getReport(ME,'extended'));
    end

    PRINT('  Replicate %d done in %.1f s\n\n', s, toc(t_rep));

end   % end SBC loop

fprintf('\nTotal SBC time: %.1f min\n', toc(t_loop_start)/60);

% ====================================================================
% SUMMARY STATISTICS
% ====================================================================
ptwise_fim = mean(covered_fim, 2, 'omitnan');   % [n_sim x 1]
ptwise_hyb = mean(covered_hyb, 2, 'omitnan');

simult_fim = all(covered_fim,  2) & ~any(isnan(covered_fim),  2);
simult_hyb = all(covered_hyb,  2) & ~any(isnan(covered_hyb),  2);

pt_by_time_fim = mean(covered_fim, 1, 'omitnan');   % [1 x n_eval]
pt_by_time_hyb = mean(covered_hyb, 1, 'omitnan');

overall_bound_hit = mean(loo_any_bound_hit(:), 'omitnan') * 100;

PRINT('\n%s\n', repmat('=',1,60));
PRINT(' SIMULATION-BASED CALIBRATION SUMMARY — AP FIM vs HybridCov\n');
PRINT('%s\n', repmat('=',1,60));
PRINT('Nominal coverage: %.0f%%\n\n', nominal_coverage*100);

for method = {'FIM','HYB'}
    name = method{1};
    switch name
        case 'FIM'; ptw=ptwise_fim; sim=simult_fim; wid=width_fim; D_m=D_fim_all;
        case 'HYB'; ptw=ptwise_hyb; sim=simult_hyb; wid=width_hyb; D_m=D_hyb_all;
    end
    PRINT('--- %s ---\n', name);
    PRINT('  Mean pointwise coverage (state 5): %.1f%%\n', mean(ptw,'omitnan')*100);
    PRINT('  Std  pointwise coverage:           %.1f%%\n', std(ptw,'omitnan')*100);
    PRINT('  Simultaneous coverage:             %.1f%%\n', mean(sim)*100);
    PRINT('  Mean band width (state 5):         %.6f\n',   mean(wid(:),'omitnan'));
    PRINT('  Mean marginal param std devs:      %s\n\n',   num2str(mean(D_m,1,'omitnan'),'%.4g '));
end
PRINT('LOO overall bound-hit rate (HYB runs): %.2f%%\n', overall_bound_hit);
PRINT('\nAll results saved to: %s\n', sbcDir);

% ====================================================================
% FIGURES
% ====================================================================
t_eval       = times_ref(2:end);
col_fim      = [0.85 0.15 0.15];
col_hyb      = [0.10 0.65 0.20];
nominal_line = nominal_coverage * 100;
unobs_label  = sprintf('State %d (unobserved)', unobs_idx);

% --- Fig 1: Pointwise coverage by time ---
fig1 = figure('Color','w','Position',[50 50 900 400]);
hold on; grid on;
plot(t_eval, pt_by_time_fim*100, '-s','Color',col_fim,'LineWidth',2,'MarkerSize',5,'DisplayName','FIM');
plot(t_eval, pt_by_time_hyb*100, '-^','Color',col_hyb,'LineWidth',2,'MarkerSize',5,'DisplayName','Hybrid');
yline(nominal_line,'k--','LineWidth',2,'DisplayName',sprintf('Nominal %.0f%%',nominal_line));
ylim([0 105]);
xlabel('Time','FontSize',12); ylabel('Coverage (%)','FontSize',12);
title(sprintf('Pointwise coverage — %s  [n=%d replicates]', unobs_label, n_sim), ...
      'FontSize',12,'FontWeight','bold');
legend('Location','best','FontSize',11);
savefig(fig1, fullfile(sbcDir,'fig1_coverage_by_time.fig'));
savefig_png(fig1,  fullfile(sbcDir,'fig1_coverage_by_time'));

% --- Fig 2: Per-replicate coverage distributions ---
fig2 = figure('Color','w','Position',[100 100 800 400]);
hold on; grid on;
histogram(ptwise_fim*100,'BinWidth',5,'FaceColor',col_fim,'FaceAlpha',0.6,'DisplayName','FIM');
histogram(ptwise_hyb*100,'BinWidth',5,'FaceColor',col_hyb,'FaceAlpha',0.6,'DisplayName','Hybrid');
xline(nominal_line,'k--','LineWidth',2,'DisplayName',sprintf('Nominal %.0f%%',nominal_line));
xlabel('Pointwise coverage per replicate (%)','FontSize',12);
ylabel('Count','FontSize',12);
title('Distribution of per-replicate coverage','FontSize',12,'FontWeight','bold');
legend('FontSize',11,'Location','northwest');
savefig(fig2, fullfile(sbcDir,'fig2_coverage_dist.fig'));
savefig_png(fig2,  fullfile(sbcDir,'fig2_coverage_dist'));

% --- Fig 3: Mean band width by time ---
fig3 = figure('Color','w','Position',[150 150 900 400]);
hold on; grid on;
plot(t_eval, mean(width_fim,1,'omitnan'), '-s','Color',col_fim,'LineWidth',2,'MarkerSize',5,'DisplayName','FIM');
plot(t_eval, mean(width_hyb,1,'omitnan'), '-^','Color',col_hyb,'LineWidth',2,'MarkerSize',5,'DisplayName','Hybrid');
xlabel('Time','FontSize',12); ylabel('Mean band width','FontSize',12);
title(sprintf('Mean prediction band width — %s', unobs_label), ...
      'FontSize',12,'FontWeight','bold');
legend('Location','best','FontSize',11);
savefig(fig3, fullfile(sbcDir,'fig3_band_width.fig'));
savefig_png(fig3,  fullfile(sbcDir,'fig3_band_width'));

% --- Fig 4: Full-data parameter recovery ---
% Subplot grid sized to n_params
ncols4 = min(n_params, 3);
nrows4 = ceil(n_params / ncols4);
fig4 = figure('Color','w','Position',[100 100 380*ncols4 300*nrows4]);
for p = 1:n_params
    subplot(nrows4, ncols4, p); hold on; grid on;
    histogram(params_fim(:,p),'FaceColor',col_fim,'FaceAlpha',0.6,'DisplayName','FIM');
    histogram(params_hyb(:,p),'FaceColor',col_hyb,'FaceAlpha',0.6,'DisplayName','Hybrid');
    xline(true_parameters(p),'k--','LineWidth',1.8,'DisplayName','True');
    xlabel('Estimate','FontSize',9); ylabel('Count','FontSize',9);
    title(param_names{p},'FontSize',10,'FontWeight','bold');
    if p == 1, legend('FontSize',8,'Location','best'); end
end
sgtitle('Full-data parameter estimates across SBC replicates', ...
        'FontSize',12,'FontWeight','bold');
savefig(fig4, fullfile(sbcDir,'fig4_param_recovery.fig'));
savefig_png(fig4,  fullfile(sbcDir,'fig4_param_recovery'));

% --- Fig 5: Marginal std dev comparison (FIM vs Hybrid vs LOO) ---
fig5 = figure('Color','w','Position',[200 200 800 360]);
hold on; grid on;
x_pos = 1:n_params;
bw    = 0.28;
bar(x_pos - bw, mean(D_fim_all,1,'omitnan'), bw, 'FaceColor',col_fim, 'FaceAlpha',0.8,'DisplayName','FIM');
bar(x_pos,      mean(D_loo_all,1,'omitnan'), bw, 'FaceColor',[0.2 0.3 0.9],'FaceAlpha',0.8,'DisplayName','LOO');
bar(x_pos + bw, mean(D_hyb_all,1,'omitnan'), bw, 'FaceColor',col_hyb, 'FaceAlpha',0.8,'DisplayName','Hybrid');
set(gca,'XTick',x_pos,'XTickLabel',param_names,'FontSize',11);
ylabel('Mean marginal std dev','FontSize',12);
title({'Parameter marginal std devs: FIM vs LOO vs Hybrid', ...
       'Hybrid inherits FIM scale by construction'},'FontSize',11,'FontWeight','bold');
legend('FontSize',10,'Location','best');
savefig(fig5, fullfile(sbcDir,'fig5_marginal_stddev.fig'));
savefig_png(fig5,  fullfile(sbcDir,'fig5_marginal_stddev'));

% --- Fig 6: LOO correlation matrix (last successful replicate) ---
if ~any(isnan(R_loo_last(:)))
    fig6 = figure('Color','w','Position',[250 250 520 460]);
    imagesc(R_loo_last); colorbar; caxis([-1 1]);
    colormap(sbc_redblue(64));
    set(gca,'XTick',1:n_params,'XTickLabel',param_names, ...
            'YTick',1:n_params,'YTickLabel',param_names,'FontSize',11);
    for ri = 1:n_params
        for ci = 1:n_params
            text(ci, ri, sprintf('%.2f', R_loo_last(ri,ci)), ...
                 'HorizontalAlignment','center','FontSize',9,'Color','k');
        end
    end
    title('LOO correlation matrix R_{LOO} (last replicate)', ...
          'FontSize',12,'FontWeight','bold');
    savefig(fig6, fullfile(sbcDir,'fig6_loo_correlation.fig'));
    savefig_png(fig6,  fullfile(sbcDir,'fig6_loo_correlation'));
end

% --- Fig 7: Calibration summary bar chart ---
methods_lbl  = {'FIM','Hybrid'};
cov_means    = [mean(ptwise_fim,'omitnan'), mean(ptwise_hyb,'omitnan')] * 100;
cov_stds     = [std(ptwise_fim,'omitnan'),  std(ptwise_hyb,'omitnan')]  * 100;
width_means  = [mean(width_fim(:),'omitnan'), mean(width_hyb(:),'omitnan')];
simult_means = [mean(simult_fim)*100, mean(simult_hyb)*100];
colors2      = [col_fim; col_hyb];

fig7 = figure('Color','w','Position',[300 100 700 620]);

subplot(3,1,1); hold on; grid on;
hb1 = bar(1:2, cov_means, 'FaceColor','flat');
hb1.CData = colors2;
errorbar(1:2, cov_means, cov_stds, 'k.','LineWidth',1.8,'CapSize',8);
yline(nominal_line,'k--','LineWidth',1.5,'DisplayName',sprintf('Nominal %.0f%%',nominal_line));
set(gca,'XTick',1:2,'XTickLabel',methods_lbl,'FontSize',11);
ylabel('Mean ptwise cov. (%)','FontSize',10);
title('Pointwise coverage (mean ± std)','FontSize',11,'FontWeight','bold');
ylim([0 105]);

subplot(3,1,2); hold on; grid on;
hb2 = bar(1:2, simult_means, 'FaceColor','flat');
hb2.CData = colors2;
set(gca,'XTick',1:2,'XTickLabel',methods_lbl,'FontSize',11);
ylabel('Simultaneous cov. (%)','FontSize',10);
title('Simultaneous coverage','FontSize',11,'FontWeight','bold');
ylim([0 105]);

subplot(3,1,3); hold on; grid on;
hb3 = bar(1:2, width_means, 'FaceColor','flat');
hb3.CData = colors2;
set(gca,'XTick',1:2,'XTickLabel',methods_lbl,'FontSize',11);
ylabel('Mean band width','FontSize',10);
title(sprintf('Mean band width — %s', unobs_label),'FontSize',11,'FontWeight','bold');

sgtitle(sprintf('SBC summary — AP example (n=%d replicates, nominal %.0f%%)', ...
                n_sim, nominal_line), 'FontSize',12,'FontWeight','bold');
savefig(fig7, fullfile(sbcDir,'fig7_summary.fig'));
savefig_png(fig7,  fullfile(sbcDir,'fig7_summary'));

% ====================================================================
% SAVE WORKSPACE
% ====================================================================
save(fullfile(sbcDir,'SBC_AP_workspace.mat'), ...
     'covered_fim','covered_hyb', ...
     'width_fim','width_hyb', ...
     'ptwise_fim','ptwise_hyb', ...
     'simult_fim','simult_hyb', ...
     'pt_by_time_fim','pt_by_time_hyb', ...
     'D_fim_all','D_hyb_all','D_loo_all', ...
     'params_fim','params_hyb', ...
     'all_loo_params','loo_any_bound_hit', ...
     'R_loo_last', ...
     'true_parameters','nominal_coverage','n_sim','alp', ...
     'times_ref','param_names','lb_params','ub_params', ...
     'is_observed','unobs_idx','Y_true','sigma');

fprintf('All results saved to  %s\n', sbcDir);
fprintf('Log written to        %s\n', logFile);

% ====================================================================
% LOCAL FUNCTIONS
% ====================================================================
function dual_print(logpath, varargin)
% Write formatted string to console and append to log file.
% Reopens in append mode on every call so parallel pool restarts
% (inside CUQDyn1_Plus / CUQDyn1_Plus_HybridCov) cannot invalidate
% the file descriptor.
    str = sprintf(varargin{:});
    fprintf('%s', str);
    fid = fopen(logpath,'a');
    if fid > 0, fprintf(fid,'%s',str); fclose(fid); end
end

function cmap = sbc_redblue(n)
% Red-white-blue diverging colormap for the LOO correlation heatmap.
    half = floor(n/2);
    r = [ones(1,half), linspace(1,0,n-half)];
    g = [linspace(0,1,half), linspace(1,0,n-half)];
    b = [linspace(0,1,half), ones(1,n-half)];
    cmap = [r(:), g(:), b(:)];
end
