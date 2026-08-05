%% diagnose_LinearCascade_known_truth.m
% Numerical sanity check for CUQDyn1_Plus using a two-state linear cascade.
%
% System:
%   x1' = -k1*x1
%   x2' =  k1*x1 - k2*x2
%
% Only x2 is observed. x1 is hidden. The analytic solution is used to
% independently compute weighted-residual sensitivities, parameter covariance,
% and hidden-state delta-method standard deviations.

clear mex; clear all; close all; clc;
exampleDir = fileparts(mfilename('fullpath'));
repoRoot = fullfile(exampleDir, '..', '..');
addpath(genpath(repoRoot));

% ========================================================================
% Problem setup
% ========================================================================
dynamics_handle = @prob_mod_dynamics_LinearCascade;
cost_handle     = @prob_mod_cost_LinearCascade;
nstates         = 2;
n_params        = 2;
state_names     = {'Hidden x1', 'Observed x2'};
param_names     = {'k1', 'k2'};

true_parameters = [0.35, 0.12];
initial_values  = [10, 0];
times           = (0:0.5:20)';
observed_idx    = 2;
alp             = 0.025;
noise_pct       = 5;
rng_seed        = 123;

opts = cuqdyn_default_options(n_params);
opts.uq.alp = alp;
opts.meigo.maxeval = n_params * 500;
opts.meigo.iterprint = 0;
opts.ode.RelTol = 1e-9;
opts.ode.AbsTol = 1e-11;
cuqdyn_set_ode_options(opts.ode);

Y_true = linear_cascade_solution(times, initial_values, true_parameters);
sigma_obs = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, noise_pct);

opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = sigma_obs;
opts.cost.sigma_is_known = true;

meigo_opts = opts.meigo;
meigo_opts.cost_opts = opts.cost;

% ========================================================================
% Synthetic data
% ========================================================================
rng(rng_seed);
Y_noisy = Y_true;
Y_noisy(2:end, observed_idx) = Y_true(2:end, observed_idx) + ...
    sigma_obs * randn(numel(times)-1, 1);

all_state_data = NaN(numel(times), nstates);
all_state_data(1, :) = initial_values;
all_state_data(:, observed_idx) = Y_noisy(:, observed_idx);
observed_data = all_state_data(:, observed_idx);

dataDir = fullfile(exampleDir, 'data');
if ~exist(dataDir, 'dir'), mkdir(dataDir); end
data_file_name = 'linear_cascade_known_truth_partobs.csv';
T_data = array2table([times, all_state_data], ...
    'VariableNames', {'time', 'x1', 'x2'});
writetable(T_data, fullfile(dataDir, data_file_name));

% ========================================================================
% CUQDyn run
% ========================================================================
timestamp = string(datetime('now'), 'yyyy-MM-dd_HH-mm-ss');
resultDir = fullfile(exampleDir, "Results_LinearCascade_known_truth_" + timestamp);
mkdir(resultDir);

[times_loaded, all_state_loaded, ic_loaded, observed_loaded, observed_idx_loaded] = ...
    loadStateData(dataDir, data_file_name, nstates);

guess_params = true_parameters .* [0.75, 1.35];
lb_params    = true_parameters .* 0.2;
ub_params    = true_parameters .* 3.0;

fprintf('\n=== LinearCascade known-truth numerical check ===\n');
fprintf('Known observation sigma for x2: %.6g\n', sigma_obs);

results = CUQDyn1_Plus(cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times_loaded, all_state_loaded, ic_loaded, observed_loaded, ...
    observed_idx_loaded, resultDir, meigo_opts);

plot_hybrid_uq(results, resultDir);
save_trajectory_nrmse_tables(results, resultDir, state_names);
diagnose_uq_quality(results, resultDir, param_names, state_names, lb_params, ub_params);

% ========================================================================
% Independent analytic covariance and hidden-state uncertainty check
% ========================================================================
theta_hat = results.parameters_init(:)';
Y_hat_analytic = linear_cascade_solution(times_loaded, ic_loaded, theta_hat);

weighted_residual_fun = @(p) analytic_weighted_residuals( ...
    p, times_loaded, ic_loaded, observed_loaded, observed_idx_loaded, opts.cost);
J_ref = complex_step_jacobian(weighted_residual_fun, theta_hat);
Cov_ref = (J_ref' * J_ref + 1e-10 * eye(n_params)) \ eye(n_params);

state_fun = @(p) reshape(linear_cascade_solution(times_loaded, ic_loaded, p), [], 1);
S_flat = complex_step_jacobian(state_fun, theta_hat);
S_ref = reshape(S_flat, numel(times_loaded), nstates, n_params);

std_ref = zeros(numel(times_loaded), nstates);
for i = 1:numel(times_loaded)
    St = squeeze(S_ref(i, :, :));
    std_ref(i, :) = sqrt(max(diag(St * Cov_ref * St'), 0));
end

cov_abs_err = norm(results.Cov_p - Cov_ref, 'fro');
cov_rel_err = cov_abs_err / max(norm(Cov_ref, 'fro'), eps);
std_hidden_abs_err = norm(results.std_y(:, 1) - std_ref(:, 1));
std_hidden_rel_err = std_hidden_abs_err / max(norm(std_ref(:, 1)), eps);
trajectory_analytic_err = max(abs(results.media_tot(:) - Y_hat_analytic(:)));

summaryTable = table( ...
    cov_abs_err, cov_rel_err, std_hidden_abs_err, std_hidden_rel_err, ...
    trajectory_analytic_err, ...
    'VariableNames', {'CovAbsFroError', 'CovRelFroError', ...
    'HiddenStdAbsError', 'HiddenStdRelError', 'MaxTrajectoryAnalyticError'});

paramTable = table(param_names(:), true_parameters(:), theta_hat(:), ...
    sqrt(diag(results.Cov_p)), sqrt(diag(Cov_ref)), ...
    'VariableNames', {'Parameter', 'TrueValue', 'Estimate', ...
    'CUQDynStdDev', 'AnalyticRefStdDev'});

hiddenStdTable = table(times_loaded(:), results.std_y(:, 1), std_ref(:, 1), ...
    abs(results.std_y(:, 1) - std_ref(:, 1)), ...
    'VariableNames', {'Time', 'CUQDynHiddenStd', 'AnalyticRefHiddenStd', ...
    'AbsDifference'});

fprintf('\n=== Independent analytic reference comparison ===\n');
disp(summaryTable);
disp(paramTable);

writetable(summaryTable, fullfile(resultDir, 'linear_cascade_numerics_summary.xlsx'), ...
    'Sheet', 'Summary');
writetable(paramTable, fullfile(resultDir, 'linear_cascade_numerics_summary.xlsx'), ...
    'Sheet', 'ParameterCovariance');
writetable(hiddenStdTable, fullfile(resultDir, 'linear_cascade_numerics_summary.xlsx'), ...
    'Sheet', 'HiddenStateStd');

save(fullfile(resultDir, 'linear_cascade_known_truth_workspace.mat'));
fprintf('\nLinearCascade known-truth outputs saved to %s\n', resultDir);

% ========================================================================
% Local analytic helpers
% ========================================================================
function Y = linear_cascade_solution(t, y0, p)
    t = t(:);
    k1 = p(1);
    k2 = p(2);
    x10 = y0(1);
    x20 = y0(2);

    x1 = x10 .* exp(-k1 .* t);
    if abs(k2 - k1) < 1e-10
        x2 = (x20 + k1 .* x10 .* t) .* exp(-k1 .* t);
    else
        x2 = x20 .* exp(-k2 .* t) + ...
            k1 .* x10 .* (exp(-k1 .* t) - exp(-k2 .* t)) ./ (k2 - k1);
    end
    Y = [x1, x2];
end

function r = analytic_weighted_residuals(p, t, y0, ydata, observed_idx, cost_opts)
    Y = linear_cascade_solution(t, y0, p);
    r = cuqdyn_weight_residuals(Y(:, observed_idx) - ydata, cost_opts);
    r = r(:);
end

function J = complex_step_jacobian(f, p0)
    h = 1e-20;
    p0 = p0(:);
    f0 = f(p0.');
    J = zeros(numel(f0), numel(p0));
    for k = 1:numel(p0)
        pc = p0;
        pc(k) = pc(k) + 1i*h;
        J(:, k) = imag(f(pc.')) / h;
    end
end
