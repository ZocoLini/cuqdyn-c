function gen_cost_replay(model)
%GEN_COST_REPLAY Layer 2.5: record every point a MATLAB MEIGO search evaluates.
%
%   gen_cost_replay('lv2')   ->  cost_replay/lv2_evals.txt
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

if nargin < 1, model = 'lv2'; end

here = fileparts(mfilename('fullpath'));
repo = fullfile(here, '..', '..', '..');
addpath(fullfile(repo, 'CUQDyn1_Plus', 'src'));

meigoPath = getenv('MEIGO64_PATH');
if isempty(meigoPath)
    meigoPath = fullfile(repo, 'CUQDyn', 'Matlab', 'MEIGO64-master');
end
addpath(genpath(meigoPath));

switch lower(model)
    case 'lv2'
        exdir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'LV');
        addpath(exdir);
        dynamics = @prob_mod_dynamics_LV;
        cost = @prob_mod_cost_LV;
        nstates = 2;
        n_params = 4;
        true_params = [0.5, 0.02, 0.02, 0.5];
        guess = true_params * 0.8;
        lb = true_params * 0.2;
        ub = true_params * 2.0;
        dataDir = fullfile(exdir, 'data');
        dataFile = 'lv2_synthetic_data_noi10_partobs_1.csv';
        noise_pct = 10;
        maxeval = 2e4;
    otherwise
        error('gen_cost_replay:model', 'Only lv2 is wired up so far.');
end

[times, ~, y0, observed_data, observed_idx] = ...
    loadStateData(dataDir, dataFile, nstates);

% Options and known-sigma weighting, exactly like gen_baseline / the runner.
opts = cuqdyn_default_options(n_params);
opts.meigo.maxeval = maxeval;
opts.meigo.iterprint = 0;
cuqdyn_set_ode_options(opts.ode);
[~, ode_opts] = cuqdyn_get_ode_options();
[ode_options, ~] = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t, y) dynamics(t, y, true_params), times, y0, ode_options);
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, noise_pct);
opts.cost.sigma_is_known = true;

meigo_opts = opts.meigo;
if isfield(meigo_opts, 'refit'), meigo_opts = rmfield(meigo_opts, 'refit'); end

% Recorder around the cost handle. MEIGO passes the extra arguments through
% to the handle unchanged, so the wrapper keeps the exact same signature.
global COST_REPLAY_LOG %#ok<GVMIS>
COST_REPLAY_LOG = zeros(0, n_params + 1);

problem.f = @(x, varargin) recorded_cost(cost, x, varargin{:});
problem.x_L = lb;
problem.x_U = ub;
problem.x_0 = guess;

rng(20260828, 'twister');   % the ONLY source of randomness, MATLAB-side
MEIGO(problem, meigo_opts, 'ESS', times, observed_data, observed_idx, ...
    dynamics, y0, ode_opts, opts.cost);

log_matrix = COST_REPLAY_LOG;
clear global COST_REPLAY_LOG

out = fullfile(here, sprintf('%s_evals.txt', model));
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
