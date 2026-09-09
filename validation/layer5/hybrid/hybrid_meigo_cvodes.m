function hybrid_meigo_cvodes(model, port, maxeval)
%HYBRID_MEIGO_CVODES The shared-optimiser experiment, one model at a time.
%
% Both pipelines share the SAME optimiser (this MATLAB session's MEIGO, same
% rng seed) and the same integrator family (CVODES, same tolerances as the C
% config). The only difference between the two runs is who evaluates the
% cost:
%
%   run A: MATLAB cost - the ode object with the 'cvodesstiff' solver
%          (SUNDIALS CVODES inside MATLAB R2024a), rtol 1e-6 / atol 1e-8.
%   run B: the C cost - cost_server (solve_ode + cuqdyn_residual_weight,
%          the exact CLI code path) over TCP on localhost:port, replying J
%          plus the residual vector so MEIGO's lsqnonlin local solver works
%          against the C cost too.
%
% The experiment MEASURES how long the two eSS trajectories stay in
% lock-step, where they first diverge, and how far apart the final optima
% land. Models: lv2, ap, sir, nfkb (same problem definitions as
% gen_baseline.m). Start the matching cost_server first:
%
%   ./cost_server <model cuqdyn config> <model data> <port>
%
% Writes hybrid_report_<model>.txt and the two evaluation logs next to this
% file, and sends "quit" to the server when done.

if nargin < 1, model = 'lv2'; end
if nargin < 2, port = 45601; end
if nargin < 3, maxeval = 1e4; end

here = fileparts(mfilename('fullpath'));
repo = fullfile(here, '..', '..', '..');
addpath(fullfile(repo, 'CUQDyn1_Plus', 'src'));
for d = {'LV', 'AP', 'SIR', 'NFKB'}
    addpath(fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', d{1}));
end
meigoPath = getenv('MEIGO64_PATH');
if isempty(meigoPath), meigoPath = fullfile(repo, 'CUQDyn', 'Matlab', 'MEIGO64-master'); end
addpath(genpath(meigoPath));

pb = local_problem(model, repo);
[times, ~, y0, observed_data, observed_idx] = ...
    loadStateData(pb.dataDir, pb.dataFile, pb.nstates);
m = numel(times);
n_resid = m * numel(observed_idx);

% Residual weighting per model, identical to gen_baseline / the C configs.
opts = cuqdyn_default_options(pb.n_params);
cuqdyn_set_ode_options(opts.ode);
[ode_options, ~] = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t, y) pb.dynamics(t, y, pb.true_params), times, y0, ode_options);
switch pb.cost_model
    case 'known_sigma_traj'
        sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, pb.noise_pct);
    case 'known_sigma_sir'
        sigma = (pb.noise_pct / 100) * mean(Y_true(2:end, 2));
    case 'none'
        sigma = ones(1, numel(observed_idx));
end
weight = 1 ./ max(abs(sigma), 1e-12);

seed = 20260904;

fprintf('=== hybrid %s: run A (MATLAB CVODES cost) ===\n', model);
global HYBRID_LOG %#ok<GVMIS>
HYBRID_LOG = zeros(0, pb.n_params + 2);
costA = @(x, varargin) log_cost(@cvodes_cost, x);
resA = run_meigo(costA, pb, maxeval, seed);
logA = HYBRID_LOG;

fprintf('=== hybrid %s: run B (C cost over TCP :%d) ===\n', model, port);
t = tcpclient('127.0.0.1', port, 'Timeout', 120);
configureTerminator(t, 'LF');
HYBRID_LOG = zeros(0, pb.n_params + 2);
costB = @(x, varargin) log_cost(@(p) tcp_cost(t, p), x);
resB = run_meigo(costB, pb, maxeval, seed);
logB = HYBRID_LOG;
writeline(t, 'quit');
clear t

% --- analysis ---
np = pb.n_params;
n = min(size(logA, 1), size(logB, 1));
same_theta = all(abs(logA(1:n, 1:np) - logB(1:n, 1:np)) <= ...
    1e-12 * max(abs(logA(1:n, 1:np)), 1), 2);
first_div = find(~same_theta, 1);
if isempty(first_div), first_div = NaN; end
prefix = min(n, max(first_div - 1, 1));
relJ = abs(logA(1:prefix, np + 1) - logB(1:prefix, np + 1)) ./ ...
    max(abs(logA(1:prefix, np + 1)), 1e-300);

fid = fopen(fullfile(here, sprintf('hybrid_report_%s.txt', model)), 'w');
out = @(varargin) both(fid, varargin{:});
out('HYBRID EXPERIMENT - %s  (seed %d, maxeval %g)\n', model, seed, maxeval);
out('run A: MEIGO + MATLAB-CVODES cost | run B: same MEIGO/seed + C cost (TCP)\n\n');
out('evaluations:            A=%d  B=%d\n', size(logA, 1), size(logB, 1));
if isnan(first_div)
    out('theta sequences:        IN LOCK-STEP for all %d common evaluations\n', n);
else
    out('theta sequences:        lock-step for %d evaluations, diverge at #%d\n', first_div - 1, first_div);
end
out('cost agreement on the common prefix (rel): median %.3e  max %.3e\n', median(relJ), max(relJ));
out('\nfinal results:\n');
out('  A: J=%.10g  theta=[%s]\n', resA.fbest, sprintf('%.8g ', resA.xbest));
out('  B: J=%.10g  theta=[%s]\n', resB.fbest, sprintf('%.8g ', resB.xbest));
out('  |thetaA-thetaB|/thetaA: median %.2e  max %.2e\n', ...
    median(abs(resA.xbest - resB.xbest) ./ max(abs(resA.xbest), 1e-300)), ...
    max(abs(resA.xbest - resB.xbest) ./ max(abs(resA.xbest), 1e-300)));
out('  |JA-JB|/JA = %.2e\n', abs(resA.fbest - resB.fbest) / max(abs(resA.fbest), 1e-300));
fclose(fid);

save_log(fullfile(here, sprintf('log_A_%s.txt', model)), logA);
save_log(fullfile(here, sprintf('log_B_%s.txt', model)), logB);

% ------------------------------------------------------------------ local --

    function [J, g, R] = cvodes_cost(p)
        try
            F = ode(ODEFcn = @(tt, yy) pb.dynamics(tt, yy, p), ...
                InitialValue = y0, InitialTime = times(1));
            F.Solver = 'cvodesstiff';
            F.RelativeTolerance = 1e-6;
            F.AbsoluteTolerance = 1e-8;
            S = solve(F, times);
            ysim = S.Solution.'; % ntimes x nstates
            Rm = (ysim(:, observed_idx) - observed_data) .* weight;
            R = Rm(:);
            J = sum(R .^ 2);
        catch
            J = 1e20;
            R = 1e10 * ones(n_resid, 1);
        end
        g = 0;
    end

    function [J, g, R] = tcp_cost(t_, p)
        writeline(t_, sprintf('%.17g ', p));
        reply = readline(t_);
        vals = sscanf(reply, '%f');
        if isempty(vals) || isnan(vals(1))
            J = 1e20;
            R = 1e10 * ones(n_resid, 1);
            g = 0;
            return;
        end
        J = vals(1);
        R = vals(2:end);
        g = 0;
    end

    function [J, g, R] = log_cost(inner, x)
        [J, g, R] = inner(x);
        HYBRID_LOG(end + 1, :) = [x(:).' J norm(R)]; %#ok<AGROW>
    end

    function res = run_meigo(cost, pb_, maxeval_, seed_)
        problem.f = cost;
        problem.x_L = pb_.lb_params;
        problem.x_U = pb_.ub_params;
        problem.x_0 = pb_.guess_params;
        mopts = opts.meigo;
        mopts.maxeval = maxeval_;
        mopts.iterprint = 0;
        if isfield(mopts, 'refit'), mopts = rmfield(mopts, 'refit'); end
        rng(seed_, 'twister');
        res = MEIGO(problem, mopts, 'ESS');
    end
end

function pb = local_problem(model, repo)
switch lower(model)
    case 'lv2'
        pb.dynamics = @prob_mod_dynamics_LV;
        pb.nstates = 2;
        pb.n_params = 4;
        pb.true_params = [0.5, 0.02, 0.02, 0.5];
        pb.guess_params = pb.true_params * 0.8;
        pb.lb_params = pb.true_params * 0.2;
        pb.ub_params = pb.true_params * 2.0;
        pb.dataDir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'LV', 'data');
        pb.dataFile = 'lv2_synthetic_data_noi10_partobs_1.csv';
        pb.cost_model = 'known_sigma_traj';
        pb.noise_pct = 10;
    case 'ap'
        pb.dynamics = @prob_mod_dynamics_AP;
        pb.nstates = 5;
        pb.n_params = 5;
        pb.true_params = [5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05];
        pb.guess_params = pb.true_params * 0.8;
        pb.lb_params = pb.true_params * 0.05;
        pb.ub_params = pb.true_params * 5.0;
        pb.dataDir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'AP', 'data');
        pb.dataFile = 'AP_measurementData_1_4.csv';
        pb.cost_model = 'none';
        pb.noise_pct = 0;
    case 'sir'
        pb.dynamics = @prob_mod_dynamics_SIR;
        pb.nstates = 3;
        pb.n_params = 2;
        pb.true_params = [0.002, 0.5];
        pb.guess_params = [0.001, 0.2];
        pb.lb_params = [0.0001, 0.01];
        pb.ub_params = [0.01, 2.0];
        pb.dataDir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'SIR', 'data');
        pb.dataFile = 'sir_data.csv';
        pb.cost_model = 'known_sigma_sir';
        pb.noise_pct = 10;
    case 'nfkb'
        pb.dynamics = @prob_mod_dynamics_NFKB;
        pb.nstates = 15;
        pb.n_params = 29;
        pb.true_params = [0.5 0.2 0.1 1 0.1 5e-7 0.0001 0.0004 0.5 ...
            0.0001 0.00002 5e-7 0.0001 0.0004 0.5 0.0003 ...
            0.0025 0.1 0.0015 0.000025 0.000125 5 ...
            0.0025 0.01 0.001 0.0005 5e-7 0.0001 0.0004];
        pb.guess_params = pb.true_params * 0.8;
        pb.lb_params = pb.true_params * 0.1;
        pb.ub_params = pb.true_params * 4.0;
        pb.dataDir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'NFKB', 'data');
        pb.dataFile = 'NFKB_synthetic_data_5n_36st_partobs10.csv';
        pb.cost_model = 'known_sigma_traj';
        pb.noise_pct = 5;
    otherwise
        error('hybrid:model', 'Unknown model %s (lv2|ap|sir|nfkb)', model);
end
end

function both(fid, varargin)
fprintf(fid, varargin{:});
fprintf(varargin{:});
end

function save_log(path, log_matrix)
fid = fopen(path, 'w');
fprintf(fid, '%d %d\n', size(log_matrix, 1), size(log_matrix, 2));
for i = 1:size(log_matrix, 1)
    fprintf(fid, '%.17g ', log_matrix(i, :));
    fprintf(fid, '\n');
end
fclose(fid);
end
