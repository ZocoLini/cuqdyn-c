function [J, g, R] = prob_mod_cost_LinearCascade(x, texp, yexp, observed_idx, ...
    dynamics_func_handle, initial_values_all_states, ode_opts, cost_opts)
%PROB_MOD_COST_LINEARCASCADE Weighted least-squares cost for LinearCascade.

if nargin < 7 || isempty(ode_opts)
    [options, ode_opts] = cuqdyn_get_ode_options();
    [~, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
else
    [options, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
end
if nargin < 8 || isempty(cost_opts)
    cost_opts = struct();
end

[~, yout_all_states] = feval(ode_solver, dynamics_func_handle, texp, ...
    initial_values_all_states, options, x);
yout_observed = yout_all_states(:, observed_idx);

R = cuqdyn_weight_residuals(yout_observed - yexp, cost_opts);
R = R(:);
J = sum(R.^2);
g = 0;

end
