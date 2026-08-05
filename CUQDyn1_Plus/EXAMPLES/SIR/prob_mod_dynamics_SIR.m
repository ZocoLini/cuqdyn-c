function dy = prob_mod_dynamics_SIR(t, y, p)
% PROB_MOD_DYNAMICS_SIR
% Standard Epidemic Model (Non-linear)
%
% STATES:
% y(1) = S (Susceptible)
% y(2) = I (Infected) - OBSERVED
% y(3) = R (Recovered)
%
% PARAMETERS:
% p(1) = beta (Infection rate)
% p(2) = gamma (Recovery rate)

    % CRITICAL: Initialize with 'like' to support Complex Step Differentiation
    dy = zeros(3, 1, 'like', y);
    
    S = y(1);
    I = y(2);
    % R = y(3); % R is decoupled in the derivative, but we track it.
    
    beta = p(1);
    gamma = p(2);
    
    % Dynamics
    % dS/dt = -beta * S * I  (The non-linear interaction)
    dy(1) = -beta * S * I;
    
    % dI/dt = beta * S * I - gamma * I
    dy(2) = beta * S * I - gamma * I;
    
    % dR/dt = gamma * I
    dy(3) = gamma * I;

end