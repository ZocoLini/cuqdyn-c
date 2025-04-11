% Function to solve the ODE system and return the solution
function solution = ODE_solve(initial_values,times,parameters)
    [T,Y] = ode45(@(t,y) prob_mod_dynamics_ap(t, y, parameters), times, initial_values);
    solution = [T,Y];
end