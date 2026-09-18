function [T, Y] = cvodes_solver(f, tspan, y0, options, varargin)
%CVODES_SOLVER ode15s-compatible front end to CVODES (BDF) through the ode object.
%
%   [T, Y] = cvodes_solver(f, tspan, y0, options)          f(t, y)
%   [T, Y] = cvodes_solver(f, tspan, y0, options, p, ...)  f(t, y, p, ...)
%
% Registered as opts.ode.solver so every integration of the MATLAB pipeline
% (cost function, trajectories) goes through the same integrator family the C
% port uses: BDF, dense linear solver, difference-quotient Jacobian, RelTol and
% per-state AbsTol from the options.

if isempty(varargin)
    rhs = f;
else
    rhs = @(t, y) f(t, y, varargin{:});
end
F = ode(ODEFcn = rhs, InitialTime = tspan(1), InitialValue = y0(:));
F.Solver = 'cvodesstiff';
F.RelativeTolerance = odeget(options, 'RelTol', 1e-6);
atol = odeget(options, 'AbsTol', 1e-8);
F.AbsoluteTolerance = atol(:).';
S = solve(F, tspan);
T = tspan(:);
Y = S.Solution.';
end
