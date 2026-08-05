%% CUQDyn1_Plus
% Main CUQDyn1_Plus workflow: global parameter estimation, leave-one-out
% conformal calibration for observed states, and FIM/delta-method uncertainty
% propagation for unobserved states.
%
% Method summary:
%   1. Fit all observed data with bounded MEIGO/eSS least squares.
%   2. Refit a leave-one-out ensemble over non-initial time points.
%   3. Build conformal prediction bands for observed states from LOO residuals.
%   4. Estimate FIM parameter covariance and propagate it to hidden states by
%      complex-step sensitivities and first-order delta-method bands.
%
% Inputs follow the legacy CUQDyn example interface: problem-specific cost and
% dynamics handles, state/parameter counts, parameter bounds, alpha, loaded CSV
% data, observed-state indices, result directory, and MEIGO/cost/refit options.
% Use CUQDyn1_Plus_HybridCov when the unobserved-state covariance should use
% FIM marginal scales with LOO-derived parameter correlations.

function [results] = CUQDyn1_Plus(cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, times, all_state_data, ...
    initial_values_all_states, observed_data, observed_idx, resultDir, meigo_opts)

if nargin < 15, meigo_opts = struct(); end
meigo_opts = cuqdyn_fill_meigo_options(meigo_opts, n_params);
[~, ode_opts] = cuqdyn_get_ode_options();
if isfield(meigo_opts, 'cost_opts')
    cost_opts = cuqdyn_fill_cost_options(meigo_opts.cost_opts);
else
    cost_opts = cuqdyn_fill_cost_options();
end
if isfield(meigo_opts, 'refit')
    refit_opts = cuqdyn_fill_refit_options(meigo_opts.refit, n_params);
else
    refit_opts = cuqdyn_fill_refit_options([], n_params);
end
if isfield(meigo_opts, 'fim')
    fim_opts = meigo_opts.fim;
else
    fim_opts = struct();
end
meigo_opts_for_results = meigo_opts;
if isfield(meigo_opts_for_results, 'cost_opts')
    meigo_opts_for_results = rmfield(meigo_opts_for_results, 'cost_opts');
end
if isfield(meigo_opts_for_results, 'refit')
    meigo_opts_for_results = rmfield(meigo_opts_for_results, 'refit');
end
if isfield(meigo_opts_for_results, 'fim')
    meigo_opts_for_results = rmfield(meigo_opts_for_results, 'fim');
end

% --- Shared core: MEIGO fit + LOO ensemble + conformal bounds ---
[parameters_init, media_tot, media_matrix, resid_loo, loo_params, ...
 UQ_lower_obs, UQ_upper_obs, m, refit_diagnostics] = cuq_loo_ensemble( ...
    cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, initial_values_all_states, ...
    observed_data, observed_idx, meigo_opts);

% --- Gaussian UQ for unobserved states (FIM covariance + delta method) ---
[UQ_lower, UQ_upper, Cov_p, std_y, fimDiagnostics, fimReliability, Cov_log] = fast_compute_hybrid_uncertainty( ...
    media_tot, observed_data, observed_idx, initial_values_all_states, ...
    times, parameters_init, nstates, n_params, m, ...
    UQ_lower_obs, UQ_upper_obs, alp, dynamics_handle, @ODE_solve, ...
    cost_opts, ode_opts, fim_opts);

% --- Pack and save ---
results = struct();
results.times                     = times;
results.all_state_data            = all_state_data;
results.observed_data             = observed_data;
results.initial_values_all_states = initial_values_all_states;
results.observed_idx              = observed_idx;
results.parameters_init           = parameters_init;
results.media_tot                 = media_tot;
results.media_matrix              = media_matrix;
results.resid_loo                 = resid_loo;
results.loo_params                = loo_params;
results.loo_refit_diagnostics     = refit_diagnostics;
results.UQ_lower                  = UQ_lower;
results.UQ_upper                  = UQ_upper;
results.Cov_p                     = Cov_p;
results.Cov_log                   = Cov_log;
results.std_y                     = std_y;
results.alp                       = alp;
results.nstates                   = nstates;
results.n_params                  = n_params;
results.options                   = struct();
results.options.meigo             = meigo_opts_for_results;
results.options.refit             = refit_opts;
results.options.ode               = ode_opts;
results.options.cost              = cost_opts;
results.options.uq                = struct('alp', alp);
results.options.fim               = cuqdyn_fill_fim_options(fim_opts, n_params);
results.diagnostics               = struct();
results.diagnostics.fim           = fimDiagnostics;
results.diagnostics.fim_reliability = fimReliability;

save(fullfile(resultDir, 'CUQDyn1_Plus_results.mat'), 'results');
save_run_options(resultDir, results.options);
fprintf('\n=== CUQDyn1_Plus complete ===\n');

end
