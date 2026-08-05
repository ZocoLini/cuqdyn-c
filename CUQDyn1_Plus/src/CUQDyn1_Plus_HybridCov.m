%% CUQDyn1_Plus_HybridCov
% CUQDyn1_Plus variant with the same full-data fit, LOO ensemble, and
% observed-state conformal bands, but a hybrid parameter covariance for
% unobserved-state delta-method propagation.
%
% Hybrid covariance:
%   Cov_p_hyb = D_FIM * R_LOO * D_FIM
%
% D_FIM contains the FIM marginal parameter standard deviations and R_LOO is
% the empirical parameter correlation matrix from the LOO parameter ensemble.
% The intent is to preserve the FIM variance scale while replacing the pure
% FIM correlation structure with a data-driven LOO correlation structure.
%
% Interface:
%   Identical to CUQDyn1_Plus; scripts can switch methods by changing only the
%   called function name.
%
% Additional result fields:
%   Cov_p_fim   FIM-only covariance diagnostic.
%   Cov_p_loo   raw LOO empirical covariance diagnostic.
%   R_loo       LOO parameter correlation matrix.
%   D_fim       FIM marginal standard-deviation diagonal matrix.

function [results] = CUQDyn1_Plus_HybridCov(cost_handle, dynamics_handle, ...
    nstates, n_params, guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, initial_values_all_states, ...
    observed_data, observed_idx, resultDir, meigo_opts)

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

% --- Hybrid FIM-scale + LOO-correlation UQ for unobserved states ---
[UQ_lower, UQ_upper, Cov_p_hyb, std_y, Cov_p_fim, Cov_p_loo, R_loo, D_fim, fimDiagnostics, fimReliability, Cov_log] = ...
    hybrid_empirCov( ...
        media_tot, observed_data, observed_idx, initial_values_all_states, ...
        times, parameters_init, nstates, n_params, m, ...
        UQ_lower_obs, UQ_upper_obs, alp, dynamics_handle, @ODE_solve, ...
        loo_params, cost_opts, ode_opts, fim_opts);

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
results.Cov_p                     = Cov_p_hyb;
results.Cov_log                   = Cov_log;
results.Cov_p_fim                 = Cov_p_fim;
results.Cov_p_loo                 = Cov_p_loo;
results.R_loo                     = R_loo;
results.D_fim                     = D_fim;
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

save(fullfile(resultDir, 'CUQDyn1_Plus_HybridCov_results.mat'), 'results');
save_run_options(resultDir, results.options);
fprintf('\n=== CUQDyn1_Plus_HybridCov complete ===\n');

end
