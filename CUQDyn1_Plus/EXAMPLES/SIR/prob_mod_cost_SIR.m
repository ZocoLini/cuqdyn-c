function [J,g,R] = prob_mod_cost_SIR(x, texp, yexp, observed_idx, dynamics_func_handle, initial_values_all_states, ode_opts, cost_opts)
% PROB_MOD_COST_SIR
% Standard cost function wrapper for CUQDyn1_Plus

    % Solver Options
    if nargin < 7 || isempty(ode_opts)
        [options, ode_opts] = cuqdyn_get_ode_options();
        [~, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
    else
        [options, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
    end
    if nargin < 8 || isempty(cost_opts), cost_opts = struct(); end
    
    % Simulate Full Model
    [~, yout_all_states] = feval(ode_solver, dynamics_func_handle, texp, initial_values_all_states, options, x);

    % Select Observed States (Likely just State 2: Infected)
    yout_observed = yout_all_states(:, observed_idx);

    % Calculate Residuals
    R = cuqdyn_weight_residuals(yout_observed - yexp, cost_opts);
    R = reshape(R, numel(R), 1);

    % Cost (Sum of Squared Errors)
    J = sum(R.^2);

    % Gradient (unused by MEIGO ESS)
    g = 0;
end
