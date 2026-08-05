%% tutorial_LV_three_prediction_UQ_methods.m
% Quick tutorial comparing the three prediction-UQ workflows on LV:
%   1. FIM delta-method bands (CUQDyn1_Plus)
%   2. HybridCov delta-method bands (CUQDyn1_Plus_HybridCov)
%   3. Optional parametric bootstrap trajectory bands
%
% This script uses deliberately small MEIGO/bootstrap settings so the full
% workflow can be tested cheaply. Increase maxeval and n_boot for production.

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% ====================================================================
% 1. Problem setup
% ====================================================================
dynamics_handle = @prob_mod_dynamics_LV;
cost_handle     = @prob_mod_cost_LV;
nstates         = 2;
n_params        = 4;
state_names     = {'Prey', 'Predator'};
param_names     = {'alpha','beta','delta','gamma'};
true_parameters = [0.5, 0.02, 0.02, 0.5];
guess_params    = true_parameters * 0.8;
lb_params       = true_parameters * 0.2;
ub_params       = true_parameters * 2.0;
alp             = 0.025;

dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
dataFile = 'lv2_synthetic_data_noi10_partobs_1.csv';
[times, all_state_data, ic, observed_data, observed_idx] = ...
    loadStateData(dataDir, dataFile, nstates);

% Settings for tutorial runs. Increase for publication-quality runs.
opts = cuqdyn_default_options(n_params, 'fast');
opts.uq.alp = alp;
opts.ode.RelTol = 1e-9;
opts.ode.AbsTol = 1e-11;
opts.meigo.maxeval = 1500;
opts.meigo.iterprint = 0;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

[ode_opts, ~] = cuqdyn_get_ode_options();
[~, true_trajectory] = ode15s(@(t,y) dynamics_handle(t, y, true_parameters), ...
    times, ic, ode_opts);
noise_pct = 10;
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = cuqdyn_synthetic_sigma_from_trajectory(true_trajectory, observed_idx, noise_pct);
opts.cost.sigma_is_known = true;
meigo_opts.cost_opts = opts.cost;

nowTime = datetime('now');
timestamp = string(nowTime, 'yyyy-MM-dd_HH-mm-ss');
tutorialDir = "Tutorial_LV_three_UQ_methods_" + timestamp;
mkdir(tutorialDir);

% ====================================================================
% 2. Method 1: FIM delta-method bands
% ====================================================================
fimDir = fullfile(tutorialDir, 'FIM');
mkdir(fimDir);
fprintf('\n=== Tutorial method 1/3: FIM delta-method UQ ===\n');
fim_results = CUQDyn1_Plus(cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, ic, observed_data, observed_idx, fimDir, meigo_opts);
plot_hybrid_uq(fim_results, fimDir);
[fim_metrics, ~] = save_trajectory_nrmse_tables(fim_results, fimDir, state_names);
diagnose_uq_quality(fim_results, fimDir, param_names, state_names, lb_params, ub_params);

% ====================================================================
% 3. Method 2: HybridCov delta-method bands
% ====================================================================
hybDir = fullfile(tutorialDir, 'HybridCov');
mkdir(hybDir);
fprintf('\n=== Tutorial method 2/3: HybridCov delta-method UQ ===\n');
hyb_results = CUQDyn1_Plus_HybridCov(cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, ic, observed_data, observed_idx, hybDir, meigo_opts);
plot_hybrid_uq(hyb_results, hybDir);
[hyb_metrics, ~] = save_trajectory_nrmse_tables(hyb_results, hybDir, state_names);
diagnose_uq_quality(hyb_results, hybDir, param_names, state_names, lb_params, ub_params);

% ====================================================================
% 4. Method 3: Bootstrap trajectory bands, starting from the FIM fit
% ====================================================================
bootDir = fullfile(tutorialDir, 'Bootstrap_from_FIM');
mkdir(bootDir);
fprintf('\n=== Tutorial method 3/3: bootstrap trajectory UQ ===\n');
boot_opts = struct();
boot_opts.n_boot = 50; % use large-enough number here
boot_opts.alp = alp;
boot_opts.meigo_opts = meigo_opts;
boot = bootstrap_trajectory_uq(fim_results, dynamics_handle, cost_handle, ...
    lb_params, ub_params, bootDir, boot_opts);

boot_results = fim_results;
boot_results.UQ_lower = boot.UQ_lower;
boot_results.UQ_upper = boot.UQ_upper;
[boot_metrics, ~] = save_trajectory_nrmse_tables(boot_results, bootDir, state_names);

fig = figure('Color','w','Position',[100 100 900 420]);
j = 2; % predator
hold on; grid on;
fill([times(:); flipud(times(:))], ...
     [boot.UQ_lower(:,j); flipud(boot.UQ_upper(:,j))], ...
     [0.2 0.6 1.0], 'FaceAlpha', 0.25, 'EdgeColor', 'none', ...
     'DisplayName', 'Bootstrap band');
plot(times, fim_results.media_tot(:,j), 'k-', 'LineWidth', 2, 'DisplayName', 'Best fit');
plot(times, fim_results.UQ_lower(:,j), 'r--', 'LineWidth', 1.5, 'DisplayName', 'FIM lower/upper');
plot(times, fim_results.UQ_upper(:,j), 'r--', 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(times, hyb_results.UQ_lower(:,j), '--', 'Color', [0.1 0.55 0.2], ...
     'LineWidth', 1.5, 'DisplayName', 'Hybrid lower/upper');
plot(times, hyb_results.UQ_upper(:,j), '--', 'Color', [0.1 0.55 0.2], ...
     'LineWidth', 1.5, 'HandleVisibility', 'off');
xlabel('Time'); ylabel('Predator');
title('LV predator: FIM vs HybridCov vs bootstrap bands');
legend('Location','best');
savefig_png(fig, fullfile(tutorialDir, 'lv_predator_three_uq_methods'));

% ====================================================================
% 5. Compact metric comparison
% ====================================================================
dataMetricTable = make_method_comparison_table( ...
    {'FIM'; 'HybridCov'; 'Bootstrap'}, ...
    {fim_metrics; hyb_metrics; boot_metrics}, ...
    state_names);

latentCoverageTable = make_latent_coverage_table( ...
    {'FIM'; 'HybridCov'; 'Bootstrap'}, ...
    {fim_results; hyb_results; boot_results}, ...
    true_trajectory, state_names);

writetable(dataMetricTable, fullfile(tutorialDir, 'three_uq_methods_metric_comparison.xlsx'), ...
    'Sheet', 'DataFitMetrics');
writetable(latentCoverageTable, fullfile(tutorialDir, 'three_uq_methods_metric_comparison.xlsx'), ...
    'Sheet', 'LatentTruthCoverage');
save(fullfile(tutorialDir, 'tutorial_workspace.mat'), ...
    'fim_results', 'hyb_results', 'boot', 'dataMetricTable', 'latentCoverageTable', ...
    'fim_metrics', 'hyb_metrics', 'boot_metrics');

fprintf('\n=== Three-method LV observed-data metric comparison ===\n');
fprintf('Note: bootstrap bands are latent trajectory bands, so observed-data coverage\n');
fprintf('      against noisy prey measurements is not the main bootstrap target.\n');
disp(dataMetricTable);
fprintf('\n=== Three-method LV latent true-trajectory coverage ===\n');
disp(latentCoverageTable);
fprintf('Tutorial outputs saved to %s\n', tutorialDir);

% ====================================================================
% Local helper
% ====================================================================
function T = make_method_comparison_table(methodNames, metricTables, stateNames)
    method = {};
    state = {};
    nData = [];
    nrmsePct = [];
    coveragePct = [];
    normWidth = [];

    for k = 1:numel(methodNames)
        M = metricTables{k};
        tableStateNames = string(M.StateName);
        for j = 1:numel(stateNames)
            row = M(tableStateNames == string(stateNames{j}), :);
            if isempty(row)
                continue;
            end
            method{end+1,1} = methodNames{k}; %#ok<AGROW>
            state{end+1,1} = stateNames{j}; %#ok<AGROW>
            nData(end+1,1) = row.NDataPoints(1); %#ok<AGROW>
            nrmsePct(end+1,1) = row.NRMSEPercent(1); %#ok<AGROW>
            coveragePct(end+1,1) = row.CoveragePercent(1); %#ok<AGROW>
            normWidth(end+1,1) = row.NormalizedMeanIntervalWidth(1); %#ok<AGROW>
        end
    end

    T = table(method, state, nData, nrmsePct, coveragePct, normWidth, ...
        'VariableNames', {'Method', 'State', 'NDataPoints', ...
        'NRMSEPercent', 'CoveragePercent', 'NormalizedMeanIntervalWidth'});
end

function T = make_latent_coverage_table(methodNames, resultStructs, trueTrajectory, stateNames)
    method = {};
    state = {};
    coveragePct = [];
    meanWidth = [];
    normalizedWidth = [];

    for k = 1:numel(methodNames)
        R = resultStructs{k};
        for j = 1:numel(stateNames)
            lo = R.UQ_lower(:,j);
            hi = R.UQ_upper(:,j);
            ytrue = trueTrajectory(:,j);
            mask = isfinite(lo) & isfinite(hi) & isfinite(ytrue);
            method{end+1,1} = methodNames{k}; %#ok<AGROW>
            state{end+1,1} = stateNames{j}; %#ok<AGROW>
            coveragePct(end+1,1) = 100 * mean(ytrue(mask) >= lo(mask) & ytrue(mask) <= hi(mask)); %#ok<AGROW>
            meanWidth(end+1,1) = mean(hi(mask) - lo(mask)); %#ok<AGROW>
            trueRange = max(ytrue(mask)) - min(ytrue(mask));
            if trueRange > 0
                normalizedWidth(end+1,1) = meanWidth(end) / trueRange; %#ok<AGROW>
            else
                normalizedWidth(end+1,1) = NaN; %#ok<AGROW>
            end
        end
    end

    T = table(method, state, coveragePct, meanWidth, normalizedWidth, ...
        'VariableNames', {'Method', 'State', 'LatentCoveragePercent', ...
        'MeanIntervalWidth', 'NormalizedMeanIntervalWidth'});
end
