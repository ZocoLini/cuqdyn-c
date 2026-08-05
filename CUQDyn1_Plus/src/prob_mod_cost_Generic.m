function [J,g,R] = prob_mod_cost_Generic(x, texp, yexp, observed_idx, dynamics_handle, y0, ode_opts, cost_opts)
    if nargin < 7 || isempty(ode_opts)
        [options, ode_opts] = cuqdyn_get_ode_options();
        [~, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
    else
        [options, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
    end
    if nargin < 8 || isempty(cost_opts), cost_opts = struct(); end
    [~, yout] = feval(ode_solver, dynamics_handle, texp, y0, options, x);

    yout_obs = yout(:, observed_idx);
    R = cuqdyn_weight_residuals(yout_obs - yexp, cost_opts);
    R = R(:);
    J = sum(R.^2);
    g = 0;
end
