%% SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit.m
% Simulation-based calibration for the three-state linear cascade.
%
% The system is linear and checked elsewhere against a matrix-exponential
% reference. This script asks a different question: over repeated noisy
% datasets generated from the known observation model, do the FIM and
% HybridCov hidden-state bands have approximately nominal coverage?
%
% Each replicate is fitted once with CUQDyn1_Plus_HybridCov. The FIM bands
% are recomputed from the same fit using results.Cov_p_fim, so FIM and
% HybridCov share the same optimizer solution, LOO ensemble, residual
% weighting, and sensitivity linearization.

clear mex; clear all; close all; clc;
exampleDir = fileparts(mfilename('fullpath'));
repoRoot = fullfile(exampleDir, '..', '..');
addpath(genpath(repoRoot));

% ========================================================================
% USER CONTROL PANEL
% ========================================================================
config = default_sharedfit_config();
n_sim             = config.n_sim;
noise_pct         = config.noise_pct;
alp               = config.alp;
rng_seed          = config.rng_seed;
calibration_mode  = config.calibration_mode;
rep_result_mode   = config.rep_result_mode;
save_rep_results  = strcmpi(rep_result_mode, 'keep');
sample_true_params = strcmpi(calibration_mode, 'prior_predictive');

% ========================================================================
% Problem setup
% ========================================================================
dynamics_handle    = @prob_mod_dynamics_LinearCascade3;
cost_handle        = @prob_mod_cost_LinearCascade3;
nstates            = 3;
n_params           = 3;
state_names        = {'Hidden x1', 'Hidden x2', 'Observed x3'};
hidden_idx         = [1, 2];
observed_idx       = 3;
param_names        = {'k1', 'k2', 'k3'};
nominal_parameters = [0.45, 0.16, 0.055];
initial_values     = [10, 0, 0];
time_points        = (0:1.0:35)';

lb_params    = nominal_parameters .* 0.15;
ub_params    = nominal_parameters .* 4.0;
guess_params = nominal_parameters .* [0.7, 1.25, 1.4];

opts = cuqdyn_default_options(n_params, 'sbc');
opts.uq.alp = alp;
opts.meigo.maxeval = config.meigo_maxeval;
opts.meigo.iterprint = 0;
opts.meigo.refit.strategy = 'local_after_global';
opts.meigo.parallel.use_parallel = false;
opts.ode.RelTol = 1e-7;
opts.ode.AbsTol = 1e-9;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;
ode_options = cuqdyn_get_ode_options();

m = numel(time_points);
n_eval = m - 1;
n_hidden = numel(hidden_idx);
nominal_coverage = 1 - 2*alp;

% ========================================================================
% Directories and logging
% ========================================================================
timestamp = string(datetime('now'), 'yyyy-MM-dd_HH-mm-ss');
sbcDir = fullfile(exampleDir, "SBC_Results_LinearCascade3_sharedfit_fast_" + timestamp);
mkdir(sbcDir);
tmpDir = fullfile(sbcDir, 'tmp_data');
mkdir(tmpDir);

logFile = fullfile(sbcDir, 'sbc_log.txt');
fid0 = fopen(logFile, 'w'); fclose(fid0);
PRINT = @(varargin) dual_print(logFile, varargin{:});

PRINT('SBC LinearCascade3 shared-fit comparison --- %s\n', timestamp);
PRINT('n_sim=%d  noise=%.2f%%  alp=%.4f  nominal=%.1f%%\n', ...
    n_sim, noise_pct, alp, nominal_coverage*100);
PRINT('calibration_mode=%s  rep_result_mode=%s  maxeval=%d\n\n', ...
    calibration_mode, rep_result_mode, opts.meigo.maxeval);

% ========================================================================
% Storage
% ========================================================================
covered_fim = NaN(n_sim, n_eval, n_hidden);
covered_hyb = NaN(n_sim, n_eval, n_hidden);
width_fim   = NaN(n_sim, n_eval, n_hidden);
width_hyb   = NaN(n_sim, n_eval, n_hidden);

success = false(n_sim, 1);
params_fit = NaN(n_sim, n_params);
params_true = NaN(n_sim, n_params);
D_fim_all = NaN(n_sim, n_params);
D_hyb_all = NaN(n_sim, n_params);

% ========================================================================
% Main SBC loop
% ========================================================================
rng(rng_seed);
PRINT('=== Starting LinearCascade3 SBC: %d replicates ===\n\n', n_sim);
t_loop_start = tic;

for s = 1:n_sim
    PRINT('%s\n', repmat('=', 1, 64));
    PRINT('REPLICATE %d / %d\n', s, n_sim);
    PRINT('%s\n', repmat('=', 1, 64));
    t_rep = tic;

    if sample_true_params
        true_parameters = sample_log_uniform(lb_params, ub_params);
    else
        true_parameters = nominal_parameters;
    end
    params_true(s, :) = true_parameters;

    Y_true = linear_cascade3_solution(time_points, initial_values, true_parameters);
    sigma_obs = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, noise_pct);

    meigo_opts_rep = meigo_opts;
    meigo_opts_rep.cost_opts = opts.cost;
    meigo_opts_rep.cost_opts.residual_model = 'known_sigma';
    meigo_opts_rep.cost_opts.sigma = sigma_obs;
    meigo_opts_rep.cost_opts.sigma_is_known = true;

    Y_noisy = Y_true;
    Y_noisy(2:end, observed_idx) = Y_true(2:end, observed_idx) + ...
        sigma_obs * randn(m-1, 1);

    all_state_data = NaN(m, nstates);
    all_state_data(1, :) = initial_values;
    all_state_data(:, observed_idx) = Y_noisy(:, observed_idx);

    tmpName = sprintf('linear_cascade3_sbc_rep%03d.csv', s);
    hdrs = {'time', 'x1', 'x2', 'x3'};
    writetable(array2table([time_points, all_state_data], ...
        'VariableNames', hdrs), fullfile(tmpDir, tmpName));

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

        [UQ_lower_fim, UQ_upper_fim] = gaussian_bands_from_cov( ...
            res_hyb.media_tot, res_hyb.Cov_p_fim, res_hyb.parameters_init, ...
            ic_rep, times_rep, dynamics_handle, alp, ode_options);

        success(s) = true;
        params_fit(s, :) = res_hyb.parameters_init;
        D_fim_all(s, :) = sqrt(diag(res_hyb.Cov_p_fim))';
        D_hyb_all(s, :) = sqrt(diag(res_hyb.Cov_p))';

        for h = 1:n_hidden
            j = hidden_idx(h);
            true_j = Y_true(2:end, j);

            lo_fim = UQ_lower_fim(2:end, j);
            hi_fim = UQ_upper_fim(2:end, j);
            lo_hyb = res_hyb.UQ_lower(2:end, j);
            hi_hyb = res_hyb.UQ_upper(2:end, j);

            covered_fim(s, :, h) = (true_j >= lo_fim) & (true_j <= hi_fim);
            covered_hyb(s, :, h) = (true_j >= lo_hyb) & (true_j <= hi_hyb);
            width_fim(s, :, h) = hi_fim - lo_fim;
            width_hyb(s, :, h) = hi_hyb - lo_hyb;
        end

        if save_rep_results
            save(fullfile(repDir, 'linear_cascade3_sharedfit_comparison.mat'), ...
                'res_hyb', 'UQ_lower_fim', 'UQ_upper_fim', 'Y_true', ...
                'Y_noisy', 'true_parameters', 'sigma_obs');
        else
            delete_if_exists(fullfile(repDir, 'CUQDyn1_Plus_HybridCov_results.mat'));
        end

        cov_fim_rep = squeeze(mean(covered_fim(s, :, :), 2, 'omitnan')) * 100;
        cov_hyb_rep = squeeze(mean(covered_hyb(s, :, :), 2, 'omitnan')) * 100;
        PRINT('  coverage FIM x1=%.1f%% x2=%.1f%% | HYB x1=%.1f%% x2=%.1f%%\n', ...
            cov_fim_rep(1), cov_fim_rep(2), cov_hyb_rep(1), cov_hyb_rep(2));
        PRINT('  Replicate %d done in %.1f s\n\n', s, toc(t_rep));

    catch ME
        PRINT('  FAILED: %s\n\n', ME.message);
    end
end

PRINT('\nTotal calibration time: %.1f min\n', toc(t_loop_start)/60);

% ========================================================================
% Summary
% ========================================================================
idx_success = success;
n_success = sum(idx_success);
if n_success == 0
    error('SBC_LinearCascade3:NoSuccessfulReplicates', ...
        'No successful replicates; inspect %s for failure messages.', logFile);
end

summaryRows = {};
for h = 1:n_hidden
    j = hidden_idx(h);
    stateName = state_names{j};

    fim_cov = matrix_by_state(covered_fim, idx_success, h);
    hyb_cov = matrix_by_state(covered_hyb, idx_success, h);
    fim_width = matrix_by_state(width_fim, idx_success, h);
    hyb_width = matrix_by_state(width_hyb, idx_success, h);

    fim_ptwise_rep = mean(fim_cov, 2, 'omitnan');
    hyb_ptwise_rep = mean(hyb_cov, 2, 'omitnan');

    summaryRows(end+1, :) = {'FIM', stateName, ...
        mean(fim_ptwise_rep, 'omitnan')*100, std(fim_ptwise_rep, 'omitnan')*100, ...
        mean(all(fim_cov, 2))*100, mean(fim_width, 'all', 'omitnan')}; %#ok<SAGROW>
    summaryRows(end+1, :) = {'HybridCov', stateName, ...
        mean(hyb_ptwise_rep, 'omitnan')*100, std(hyb_ptwise_rep, 'omitnan')*100, ...
        mean(all(hyb_cov, 2))*100, mean(hyb_width, 'all', 'omitnan')}; %#ok<SAGROW>
end

summaryTable = cell2table(summaryRows, 'VariableNames', ...
    {'Method', 'State', 'MeanPointwiseCoveragePercent', ...
    'StdPointwiseCoveragePercent', 'SimultaneousCoveragePercent', ...
    'MeanBandWidth'});

fprintf('\n%s\n LinearCascade3 shared-fit SBC: FIM vs HybridCov\n%s\n', ...
    repmat('=', 1, 70), repmat('=', 1, 70));
fprintf('Nominal coverage: %.1f%%\n', nominal_coverage*100);
fprintf('Successful replicates: %d / %d\n\n', n_success, n_sim);
disp(summaryTable);

writetable(summaryTable, fullfile(sbcDir, 'linear_cascade3_sbc_summary.xlsx'), ...
    'Sheet', 'Summary');

% Coverage-by-time tables and figures.
t_eval = time_points(2:end);
coverageByTimeRows = {};
for h = 1:n_hidden
    for tt = 1:n_eval
        coverageByTimeRows(end+1, :) = {t_eval(tt), state_names{hidden_idx(h)}, ...
            mean(covered_fim(idx_success, tt, h), 'omitnan')*100, ...
            mean(covered_hyb(idx_success, tt, h), 'omitnan')*100, ...
            mean(width_fim(idx_success, tt, h), 'omitnan'), ...
            mean(width_hyb(idx_success, tt, h), 'omitnan')}; %#ok<SAGROW>
    end
end
coverageByTimeTable = cell2table(coverageByTimeRows, 'VariableNames', ...
    {'Time', 'State', 'FIMCoveragePercent', 'HybridCoveragePercent', ...
    'FIMMeanWidth', 'HybridMeanWidth'});
writetable(coverageByTimeTable, fullfile(sbcDir, 'linear_cascade3_sbc_summary.xlsx'), ...
    'Sheet', 'CoverageByTime');

fig1 = figure('Color', 'w', 'Position', [50 50 1100 420]);
for h = 1:n_hidden
    subplot(1, 2, h); hold on; grid on;
    fim_cov = matrix_by_state(covered_fim, idx_success, h);
    hyb_cov = matrix_by_state(covered_hyb, idx_success, h);
    plot(t_eval, mean(fim_cov, 1, 'omitnan')*100, ...
        'r-s', 'LineWidth', 1.8, 'MarkerSize', 4, 'DisplayName', 'FIM');
    plot(t_eval, mean(hyb_cov, 1, 'omitnan')*100, ...
        'g-^', 'LineWidth', 1.8, 'MarkerSize', 4, 'DisplayName', 'HybridCov');
    yline(nominal_coverage*100, 'k--', 'LineWidth', 1.5, ...
        'DisplayName', sprintf('Nominal %.0f%%', nominal_coverage*100));
    ylim([0 105]);
    xlabel('Time'); ylabel('Coverage (%)');
    title(sprintf('%s pointwise coverage', state_names{hidden_idx(h)}));
    legend('Location', 'south');
end
sgtitle(sprintf('LinearCascade3 hidden-state coverage [successful n=%d]', n_success));
savefig_png(fig1, fullfile(sbcDir, 'fig1_hidden_coverage_by_time'));

fig2 = figure('Color', 'w', 'Position', [100 100 1100 420]);
for h = 1:n_hidden
    subplot(1, 2, h); hold on; grid on;
    fim_width = matrix_by_state(width_fim, idx_success, h);
    hyb_width = matrix_by_state(width_hyb, idx_success, h);
    plot(t_eval, mean(fim_width, 1, 'omitnan'), ...
        'r-s', 'LineWidth', 1.8, 'MarkerSize', 4, 'DisplayName', 'FIM');
    plot(t_eval, mean(hyb_width, 1, 'omitnan'), ...
        'g-^', 'LineWidth', 1.8, 'MarkerSize', 4, 'DisplayName', 'HybridCov');
    xlabel('Time'); ylabel('Mean band width');
    title(sprintf('%s mean band width', state_names{hidden_idx(h)}));
    legend('Location', 'best');
end
sgtitle('LinearCascade3 hidden-state band widths');
savefig_png(fig2, fullfile(sbcDir, 'fig2_hidden_band_widths'));

save(fullfile(sbcDir, 'SBC_LinearCascade3_sharedfit_workspace.mat'), ...
    'covered_fim', 'covered_hyb', 'width_fim', 'width_hyb', ...
    'success', 'n_success', 'params_fit', 'params_true', ...
    'D_fim_all', 'D_hyb_all', 'summaryTable', 'coverageByTimeTable', ...
    'nominal_parameters', 'nominal_coverage', 'n_sim', 'alp', 'noise_pct', ...
    'time_points', 'state_names', 'hidden_idx', 'param_names', ...
    'lb_params', 'ub_params', 'guess_params', 'config');

fprintf('All results saved to  %s\n', sbcDir);
fprintf('Log written to        %s\n', logFile);

% ========================================================================
% Local functions
% ========================================================================
function config = default_sharedfit_config()
    config = struct();
    config.n_sim = 50;
    config.noise_pct = 7.5;
    config.alp = 0.025;
    config.rng_seed = 777;
    config.calibration_mode = 'conditional';  % 'conditional' or 'prior_predictive'
    config.rep_result_mode = 'discard';       % 'discard' or 'keep'
    config.meigo_maxeval = 3 * 700;
end

function p = sample_log_uniform(lb, ub)
    p = exp(log(lb) + rand(size(lb)) .* (log(ub) - log(lb)));
end

function M = matrix_by_state(A, row_idx, state_pos)
    M = A(row_idx, :, state_pos);
    M = reshape(M, [], size(A, 2));
end

function Y = linear_cascade3_solution(t, y0, p)
    t = t(:);
    A = cascade_matrix(p);
    Y = zeros(numel(t), numel(y0));
    for ii = 1:numel(t)
        Y(ii, :) = (expm(A .* t(ii)) * y0(:)).';
    end
end

function A = cascade_matrix(p)
    k1 = p(1);
    k2 = p(2);
    k3 = p(3);
    A = [-k1,  0,   0; ...
          k1, -k2,  0; ...
          0,   k2, -k3];
end

function [UQ_lower, UQ_upper, std_y] = gaussian_bands_from_cov( ...
        media_tot, Cov_p, parameters_init, initial_values, times, ...
        dynamics_handle, alp, ode_options)
    [m, nstates] = size(media_tot);
    n_params = numel(parameters_init);
    S = zeros(m, nstates, n_params);
    h = 1e-20;

    for kk = 1:n_params
        p_complex = parameters_init;
        p_complex(kk) = p_complex(kk) + 1i*h;
        sol = ODE_solve(initial_values, times, p_complex, dynamics_handle, ode_options);
        S(:, :, kk) = imag(sol(:, 2:end)) / h;
    end

    Var_y = zeros(m, nstates);
    for tt = 1:m
        St = squeeze(S(tt, :, :));
        if nstates == 1
            St = St(:)';
        end
        Var_y(tt, :) = diag(St * Cov_p * St.');
    end

    std_y = sqrt(max(Var_y, 0));
    z = norminv(1 - alp);
    UQ_lower = media_tot - z * std_y;
    UQ_upper = media_tot + z * std_y;
    UQ_lower(1, :) = initial_values;
    UQ_upper(1, :) = initial_values;
end

function delete_if_exists(filePath)
    if exist(filePath, 'file')
        delete(filePath);
    end
end

function savefig_png(figHandle, basePath)
    basePath = char(basePath);
    savefig(figHandle, [basePath, '.fig']);
    exportgraphics(figHandle, [basePath, '.png'], 'Resolution', 300);
    try
        exportgraphics(figHandle, [basePath, '.pdf'], 'ContentType', 'vector');
    catch ME
        warning('SBC_LinearCascade3:PDFExportFailed', ...
            'Could not export %s.pdf: %s', basePath, ME.message);
    end
    try
        print(figHandle, [basePath, '.eps'], '-depsc', '-painters');
    catch ME
        warning('SBC_LinearCascade3:EPSExportFailed', ...
            'Could not export %s.eps: %s', basePath, ME.message);
    end
end

function dual_print(logpath, varargin)
    str = sprintf(varargin{:});
    fprintf('%s', str);
    fid = fopen(logpath, 'a');
    if fid > 0
        fprintf(fid, '%s', str);
        fclose(fid);
    end
end
