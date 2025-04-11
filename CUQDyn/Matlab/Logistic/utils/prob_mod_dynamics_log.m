% Define the logistic growth ODE
function dy = prob_mod_dynamics_log(t, y, p)
    dy = p(1) * y * (1 - y / p(2));
return
