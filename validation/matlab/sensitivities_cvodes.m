function S = sensitivities_cvodes(dynamics, theta, y0, times, ode_opts)
%SENSITIVITIES_CVODES dy/dtheta by CVODES forward sensitivity analysis.
%
% Returns S(i, j, k) = d y_j(t_i) / d theta_k, the layout cuqdyn_fim_covariance
% expects. Replaces the complex-step loop of the published pipeline, which
% cannot run through CVODES (no complex arithmetic); the C port computes its
% sensitivities the same way (CVodeSensInit).

F = ode(ODEFcn = @(t, y, p) dynamics(t, y, p), InitialTime = times(1), ...
    InitialValue = y0(:), Parameters = theta(:).');
F.Solver = 'cvodesstiff';
F.RelativeTolerance = ode_opts.RelTol;
atol = ode_opts.AbsTol;
F.AbsoluteTolerance = atol(:).';
F.Sensitivity = odeSensitivity;
sol = solve(F, times);
S = permute(sol.Sensitivity, [3 1 2]);   % nstates x n_params x m  ->  m x nstates x n_params
end
