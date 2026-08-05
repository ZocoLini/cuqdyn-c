function [parameters_init, media_tot, media_matrix, resid_loo, loo_params, ...
          UQ_lower_obs, UQ_upper_obs, m, refit_diagnostics] = ...
    cuq_loo_ensemble(cost_handle, dynamics_handle, nstates, n_params, ...
                     guess_params, lb_params, ub_params, alp, ...
                     times, all_state_data, initial_values_all_states, ...
                     observed_data, observed_idx, meigo_opts)
% CUQ_LOO_ENSEMBLE  Shared computational core for CUQDyn1_Plus and
%                   CUQDyn1_Plus_HybridCov.
%
% Performs the expensive steps that are identical across both UQ methods:
%   1. Fit the full dataset with MEIGO/eSS using the supplied cost function.
%   2. Refit m-1 leave-one-out datasets, omitting one post-initial time point
%      per refit.
%   3. Solve the ODE for each LOO parameter vector.
%   4. Build observed-state jackknife+/conformal lower and upper bands.
%
% The function accepts the legacy example interface used by CUQDyn1_Plus. The
% observed-state pattern is supplied as observed_idx, normally inferred from
% the CSV by loadStateData. Refit behavior is controlled by meigo_opts.refit:
% 'global' repeats eSS for each LOO fit, while 'local_after_global' performs
% guarded local refits with optional global fallback.
%
% OUTPUTS
%   parameters_init  [1 x n_params]        best-fit parameters (full data)
%   media_tot        [m x nstates]         best-fit ODE trajectory (all states)
%   media_matrix     [m x nstates x m-1]   LOO ODE trajectories
%   resid_loo        [m-1 x n_obs]         LOO absolute residuals at held-out points
%   loo_params       [m-1 x n_params]      LOO parameter vectors
%   UQ_lower_obs     [m x n_obs]           conformal lower bounds (observed states)
%   UQ_upper_obs     [m x n_obs]           conformal upper bounds (observed states)
%   m                scalar                number of time points
%   refit_diagnostics struct array          local/global refit diagnostics

% ====================================================================
% 1. MEIGO GLOBAL FIT
% ====================================================================

% --- MEIGO options: apply defaults for any field not supplied by caller ---
if nargin < 14 || isempty(meigo_opts), meigo_opts = struct(); end
opts = cuqdyn_fill_meigo_options(meigo_opts, n_params);
[~, ode_opts] = cuqdyn_get_ode_options();
if isfield(opts, 'cost_opts')
    cost_opts = cuqdyn_fill_cost_options(opts.cost_opts);
else
    cost_opts = cuqdyn_fill_cost_options();
end
if isfield(opts, 'refit')
    refit_opts = cuqdyn_fill_refit_options(opts.refit, n_params);
else
    refit_opts = cuqdyn_fill_refit_options([], n_params);
end
if isfield(opts, 'cost_opts')
    opts = rmfield(opts, 'cost_opts');
end
if isfield(opts, 'refit')
    opts = rmfield(opts, 'refit');
end
if isfield(opts, 'fim')
    opts = rmfield(opts, 'fim');
end
use_parallel = true;
if isfield(opts, 'parallel')
    parallel_opts = opts.parallel;
    if isfield(parallel_opts, 'use_parallel')
        use_parallel = logical(parallel_opts.use_parallel);
    end
    opts = rmfield(opts, 'parallel');
end

problem.f         = cost_handle;
problem.x_L       = lb_params;
problem.x_U       = ub_params;
problem.x_0       = guess_params;

m = size(all_state_data, 1);

fprintf('Running initial fit using all data...\n');
Results_tot     = MEIGO(problem, opts, 'ESS', times, observed_data, ...
                         observed_idx, dynamics_handle, initial_values_all_states, ...
                         ode_opts, cost_opts);
parameters_init = Results_tot.xbest;

sol_full  = ODE_solve(initial_values_all_states, times, parameters_init, dynamics_handle, ode_opts);
media_tot = sol_full(:, 2:end);

% ====================================================================
% 2. LOO ENSEMBLE
% ====================================================================
fprintf('LOO ensemble...\n');
if use_parallel
    cuq_parpool();
else
    fprintf('Parallel LOO disabled; running LOO refits sequentially.\n');
end

media_matrix = NaN(m, nstates, m-1);
resid_loo    = NaN(m-1, length(observed_idx));
loo_params   = NaN(m-1, n_params);
refit_method = cell(m-1, 1);
refit_local_exitflag = NaN(m-1, 1);
refit_seed_cost = NaN(m-1, 1);
refit_local_cost = NaN(m-1, 1);
refit_final_cost = NaN(m-1, 1);
refit_used_global_fallback = false(m-1, 1);
refit_local_failed = false(m-1, 1);
refit_bound_hit = false(m-1, 1);
refit_large_parameter_move = false(m-1, 1);

if use_parallel
    parfor i = 2:m
        t_loo      = times([1:i-1, i+1:end]);
        y_loo      = observed_data([1:i-1, i+1:end], :);
        [params_loo, fit_info] = cuq_fit_repeated_problem(problem, opts, ...
            t_loo, y_loo, observed_idx, dynamics_handle, initial_values_all_states, ...
            ode_opts, cost_opts, parameters_init, lb_params, ub_params, refit_opts);
        sol        = ODE_solve(initial_values_all_states, times, params_loo, dynamics_handle, ode_opts);
        media_matrix(:, :, i-1) = sol(:, 2:end);
        resid_loo(i-1, :)       = abs(observed_data(i, :) - sol(i, observed_idx + 1));
        loo_params(i-1, :)      = params_loo;
        refit_method{i-1} = fit_info.method;
        refit_local_exitflag(i-1) = fit_info.local_exitflag;
        refit_seed_cost(i-1) = fit_info.seed_cost;
        refit_local_cost(i-1) = fit_info.local_cost;
        refit_final_cost(i-1) = fit_info.final_cost;
        refit_used_global_fallback(i-1) = fit_info.used_global_fallback;
        refit_local_failed(i-1) = fit_info.local_failed;
        refit_bound_hit(i-1) = fit_info.bound_hit;
        refit_large_parameter_move(i-1) = fit_info.large_parameter_move;
    end
    delete(gcp('nocreate'));
else
    for i = 2:m
        t_loo      = times([1:i-1, i+1:end]);
        y_loo      = observed_data([1:i-1, i+1:end], :);
        [params_loo, fit_info] = cuq_fit_repeated_problem(problem, opts, ...
            t_loo, y_loo, observed_idx, dynamics_handle, initial_values_all_states, ...
            ode_opts, cost_opts, parameters_init, lb_params, ub_params, refit_opts);
        sol        = ODE_solve(initial_values_all_states, times, params_loo, dynamics_handle, ode_opts);
        media_matrix(:, :, i-1) = sol(:, 2:end);
        resid_loo(i-1, :)       = abs(observed_data(i, :) - sol(i, observed_idx + 1));
        loo_params(i-1, :)      = params_loo;
        refit_method{i-1} = fit_info.method;
        refit_local_exitflag(i-1) = fit_info.local_exitflag;
        refit_seed_cost(i-1) = fit_info.seed_cost;
        refit_local_cost(i-1) = fit_info.local_cost;
        refit_final_cost(i-1) = fit_info.final_cost;
        refit_used_global_fallback(i-1) = fit_info.used_global_fallback;
        refit_local_failed(i-1) = fit_info.local_failed;
        refit_bound_hit(i-1) = fit_info.bound_hit;
        refit_large_parameter_move(i-1) = fit_info.large_parameter_move;
    end
end

refit_diagnostics = table((2:m)', string(refit_method), refit_local_exitflag, ...
    refit_seed_cost, refit_local_cost, refit_final_cost, ...
    refit_used_global_fallback, refit_local_failed, refit_bound_hit, ...
    refit_large_parameter_move, ...
    'VariableNames', {'HeldOutTimeIndex', 'Method', 'LocalExitFlag', ...
    'SeedCost', 'LocalCost', 'FinalCost', 'UsedGlobalFallback', ...
    'LocalFailed', 'BoundHit', 'LargeParameterMove'});

fprintf('LOO refit strategy: %s | local=%d global=%d fallback=%d local_failed=%d\n', ...
    refit_opts.strategy, sum(refit_diagnostics.Method == "local"), ...
    sum(refit_diagnostics.Method == "global"), ...
    sum(refit_diagnostics.UsedGlobalFallback), ...
    sum(refit_diagnostics.LocalFailed));

% ====================================================================
% 3. CONFORMAL BOUNDS FOR OBSERVED STATES
% ====================================================================
UQ_lower_obs = NaN(m, length(observed_idx));
UQ_upper_obs = NaN(m, length(observed_idx));
UQ_lower_obs(1, :) = observed_data(1, :);
UQ_upper_obs(1, :) = observed_data(1, :);

for j = 1:length(observed_idx)
    state_idx = observed_idx(j);
    for i = 2:m
        ens = squeeze(media_matrix(i, state_idx, :));
        res = resid_loo(:, j);
        UQ_lower_obs(i, j) = quantile(ens - res, alp);
        UQ_upper_obs(i, j) = quantile(ens + res, 1 - alp);
    end
end

end
