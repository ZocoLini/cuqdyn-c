function [J,g,R]=prob_mod_cost_LV(x,texp,yexp, observed_idx, dynamics_func_handle, initial_values_all_states, ode_opts, cost_opts)
% prob_mod_cost: Cost function and residuals for fully or partially observed systems.
% MODIFIED TO HANDLE UNOBSERVED STATES
% JRB - OCT-2025
% This function is called by MEIGO. It simulates the full model but only
% calculates the cost (J) based on the states specified in 'observed_idx'.
%
% CHANGED: Now accepts 'dynamics_func_handle' as a 5th argument

% --- Simulate the FULL model (all 2 states) ---

% CHANGED: Using passed 'dynamics_func_handle' and shared solver options.
if nargin < 7 || isempty(ode_opts)
    [options, ode_opts] = cuqdyn_get_ode_options();
    [~, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
else
    [options, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
end
if nargin < 8 || isempty(cost_opts), cost_opts = struct(); end
[~,yout_all_states] = feval(ode_solver,dynamics_func_handle,texp,initial_values_all_states,options,x);

% --- Select ONLY the observed states from the simulation output ---
yout_observed = yout_all_states(:, observed_idx);

% --- Calculate Residuals and Cost (J) ---
% Compare the simulated observed states (yout_observed) with the
% experimental data (yexp), which now have matching dimensions.
R = cuqdyn_weight_residuals(yout_observed - yexp, cost_opts);

% Reshape residuals for the optimizer
R = reshape(R,numel(R),1);

% Calculate the sum of squared errors
J = sum(R.^2);

% Gradient (not used)
g=0;
return
