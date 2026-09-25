function pb = layer5_problem(settings_file)
%LAYER5_PROBLEM The layer-5 problem, identical for the MEIGO server and the MATLAB pipeline.
%
% The problem of settings_file (matlab/load_problem.m) with the two things
% layer 5 changes in the reference set-up:
%   - every integration goes through CVODES (cvodes_solver), like the C port;
%   - MEIGO's local solver is dhc, the gradient-free solver of the sacess
%     configs (tol 2 = threshold 1e-8, as in the XML). lsqnonlin, the reference
%     setting, works on the residual vector with finite-difference Jacobians, so
%     a 1e-10 disagreement between the two CVODES costs becomes a slow drift of
%     theta that no eSS decision ever took; dhc only compares costs, so the two
%     sides can part only on a discrete decision.
%     CUQDYN_L5_LOCAL_SOLVER=lsqnonlin restores the reference setting.

here = fileparts(mfilename('fullpath'));
addpath(here);

local_solver = getenv('CUQDYN_L5_LOCAL_SOLVER');
if isempty(local_solver), local_solver = 'dhc'; end

pb = load_problem(settings_file, 'Solver', 'cvodes', 'LocalSolver', local_solver);
if ~pb.has_meigo
    error('layer5_problem:meigo', 'MEIGO64 not found (looked in %s).', pb.meigo_dir);
end
end
