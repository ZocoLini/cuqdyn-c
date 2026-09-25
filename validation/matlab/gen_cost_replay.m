function gen_cost_replay(settings_file)
%GEN_COST_REPLAY Layer 3: record every point a MATLAB MEIGO search evaluates.
%
%   gen_cost_replay(settings_file)   ->  references/<name>_evals.txt
%
% settings_file describes the problem (matlab/load_problem.m); the intended
% caller is  validation/run_validation.sh references --problem=lv2.
%
% This implements the "shared randomness" idea: ALL the randomness lives on
% the MATLAB side. One seeded MEIGO/eSS fit runs here with the cost handle
% wrapped in a recorder, so every parameter vector theta_k the optimiser
% chose to evaluate - thousands of points covering exactly the region a real
% search visits, bounds included - is frozen to a file together with the
% MATLAB cost value J_k (ode15s + the model's weighting).
%
% The C side (test_cost_replay.c) then replays the SAME theta sequence
% through the C cost machinery (CVODES + cuqdyn_residual_weight) and compares
% J point by point. No optimiser runs in C, so the comparison is fully
% deterministic: the frozen sequence plays the role a shared RNG would.
%
% Why not drive the C cost from MATLAB's MEIGO live (MEX/engine)? Because it
% would NOT be deterministic anyway: the two cost implementations differ at
% floating-point roundoff, eSS takes discrete accept/reject decisions on
% those values, and one flipped comparison makes the searches diverge with no
% bug present. Freezing the sequence keeps the coverage and removes the
% divergence channel.
%
% File format: "n_evals n_params" header, then one row per evaluation:
% "theta_1 ... theta_p J".

here = fileparts(mfilename('fullpath'));
addpath(here);

pb = load_problem(settings_file);
if ~pb.has_meigo
    error('gen_cost_replay:meigo', 'MEIGO64 not found (looked in %s).', pb.meigo_dir);
end
model = pb.name;
n_params = pb.n_params;
opts = pb.opts;
ode_opts = pb.ode_opts;

meigo_opts = opts.meigo;
if isfield(meigo_opts, 'refit'), meigo_opts = rmfield(meigo_opts, 'refit'); end

% Recorder around the cost handle. MEIGO passes the extra arguments through
% to the handle unchanged, so the wrapper keeps the exact same signature.
global COST_REPLAY_LOG %#ok<GVMIS>
COST_REPLAY_LOG = zeros(0, n_params + 1);

problem.f = @(x, varargin) recorded_cost(pb.cost, x, varargin{:});
problem.x_L = pb.lb_params;
problem.x_U = pb.ub_params;
problem.x_0 = pb.guess_params;

rng(20260828, 'twister');   % the ONLY source of randomness, MATLAB-side
MEIGO(problem, meigo_opts, 'ESS', pb.times, pb.observed_data, pb.observed_idx, ...
    pb.dynamics, pb.y0, ode_opts, opts.cost);

log_matrix = COST_REPLAY_LOG;
clear global COST_REPLAY_LOG

out = fullfile(here, '..', 'references', sprintf('%s_evals.txt', model));
fid = fopen(out, 'w');
fprintf(fid, '%d %d\n', size(log_matrix, 1), n_params);
for i = 1:size(log_matrix, 1)
    fprintf(fid, '%.17g ', log_matrix(i, :));
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('Recorded %d cost evaluations -> %s\n', size(log_matrix, 1), out);
end

function [J, g, R] = recorded_cost(inner, x, varargin)
global COST_REPLAY_LOG %#ok<GVMIS>
[J, g, R] = inner(x, varargin{:});
COST_REPLAY_LOG(end + 1, :) = [x(:).' J]; %#ok<AGROW>
end
