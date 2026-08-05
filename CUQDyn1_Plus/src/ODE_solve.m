% Function to solve the ODE system and return the solution
%  Added 4th argument 'dynamics_func_handle'
function solution = ODE_solve(initial_values,times,parameters, dynamics_func_handle, ode_opts)
    % Use the configured ODE solver and options.
    if nargin < 5 || isempty(ode_opts)
        [options, ode_opts] = cuqdyn_get_ode_options();
        [~, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
    else
        [options, ode_solver] = cuqdyn_odeset_from_options(ode_opts);
    end
    % Use the passed dynamics_func_handle instead of hard-coded dynamics
    [T,Y] = feval(ode_solver, @(t,y) dynamics_func_handle(t, y, parameters), ...
        times, initial_values, options);
    solution = [T,Y];
end


