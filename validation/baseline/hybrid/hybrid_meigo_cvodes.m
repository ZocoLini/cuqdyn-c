function hybrid_meigo_cvodes(port, maxeval)
%HYBRID_MEIGO_CVODES The shared-optimiser experiment David specified.
%
% Both pipelines share the SAME optimiser (this MATLAB session's MEIGO, same
% rng seed) and the same integrator family (CVODES, same tolerances as the C
% config). The only difference between the two runs is who evaluates the
% cost:
%
%   run A: MATLAB cost - the ode object with the 'cvodesstiff' solver
%          (SUNDIALS CVODES inside MATLAB R2024a), rtol 1e-6 / atol 1e-8.
%   run B: the C cost - cost_server (solve_ode + cuqdyn_residual_weight,
%          the exact CLI code path) over TCP on localhost:port.
%
% If the two costs were bitwise equal at every theta, both searches would be
% identical. They differ at floating-point level, so the experiment MEASURES
% the consequence instead of assuming it: how long the two eSS trajectories
% stay in lock-step, where they first diverge, and how far apart the final
% optima land.
%
% Usage: start the server first (WSL):
%   ./cost_server <lv2 cuqdyn config> <lv2 data> 45601
% then:
%   hybrid_meigo_cvodes(45601)          % default maxeval 1e4
%
% Writes hybrid_report.txt and the two evaluation logs next to this file.

if nargin < 1, port = 45601; end
if nargin < 2, maxeval = 1e4; end

here = fileparts(mfilename('fullpath'));
repo = fullfile(here, '..', '..', '..');
addpath(fullfile(repo, 'CUQDyn1_Plus', 'src'));
addpath(fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'LV'));
meigoPath = getenv('MEIGO64_PATH');
if isempty(meigoPath), meigoPath = fullfile(repo, 'CUQDyn', 'Matlab', 'MEIGO64-master'); end
addpath(genpath(meigoPath));

% --- LV2 problem, same numbers as gen_baseline / the C configs ---
true_params = [0.5, 0.02, 0.02, 0.5];
lb = true_params * 0.2;
ub = true_params * 2.0;
guess = true_params * 0.8;
nstates = 2;

dataDir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'LV', 'data');
[times, ~, y0, observed_data, observed_idx] = ...
    loadStateData(dataDir, 'lv2_synthetic_data_noi10_partobs_1.csv', nstates);

% Known-sigma weighting, identical to the C XML (sigma from true trajectory).
opts = cuqdyn_default_options(4);
cuqdyn_set_ode_options(opts.ode);
[ode_options, ~] = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t, y) prob_mod_dynamics_LV(t, y, true_params), times, y0, ode_options);
sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, 10);
weight = 1 ./ max(abs(sigma), 1e-12);

seed = 20260904;

% --- run A: MATLAB cost with CVODES ---
global HYBRID_LOG %#ok<GVMIS>
HYBRID_LOG = zeros(0, 6);
costA = @(x, varargin) log_cost(@cvodes_cost, x);
resA = run_meigo(costA, guess, lb, ub, maxeval, seed);
logA = HYBRID_LOG;

% --- run B: C cost over TCP ---
t = tcpclient('127.0.0.1', port, 'Timeout', 60);
configureTerminator(t, 'LF');
HYBRID_LOG = zeros(0, 6);
costB = @(x, varargin) log_cost(@(p) tcp_cost(t, p), x);
resB = run_meigo(costB, guess, lb, ub, maxeval, seed);
logB = HYBRID_LOG;
writeline(t, 'quit');
clear t

% --- analysis ---
n = min(size(logA, 1), size(logB, 1));
same_theta = all(abs(logA(1:n, 1:4) - logB(1:n, 1:4)) <= ...
    1e-12 * max(abs(logA(1:n, 1:4)), 1), 2);
first_div = find(~same_theta, 1);
if isempty(first_div), first_div = NaN; end

relJ = abs(logA(1:n, 5) - logB(1:n, 5)) ./ max(abs(logA(1:n, 5)), 1e-300);

fid = fopen(fullfile(here, 'hybrid_report.txt'), 'w');
out = @(varargin) both(fid, varargin{:});
out('HYBRID EXPERIMENT  (seed %d, maxeval %g)\n', seed, maxeval);
out('run A: MEIGO + MATLAB-CVODES cost | run B: same MEIGO/seed + C cost (TCP)\n\n');
out('evaluations:            A=%d  B=%d\n', size(logA, 1), size(logB, 1));
if isnan(first_div)
    out('theta sequences:        IN LOCK-STEP for all %d common evaluations\n', n);
else
    out('theta sequences:        lock-step for %d evaluations, diverge at #%d\n', first_div - 1, first_div);
end
out('cost agreement on the common prefix (rel): median %.3e  max %.3e\n', ...
    median(relJ(1:min(n, max(first_div - 1, 1)))), max(relJ(1:min(n, max(first_div - 1, 1)))));
out('\nfinal results:\n');
out('  A: J=%.10g  theta=[%s]\n', resA.fbest, sprintf('%.8g ', resA.xbest));
out('  B: J=%.10g  theta=[%s]\n', resB.fbest, sprintf('%.8g ', resB.xbest));
out('  |thetaA-thetaB|/thetaA = [%s]\n', ...
    sprintf('%.2e ', abs(resA.xbest - resB.xbest) ./ max(abs(resA.xbest), 1e-300)));
fclose(fid);

save_log(fullfile(here, 'log_A_matlab_cvodes.txt'), logA);
save_log(fullfile(here, 'log_B_c_cost.txt'), logB);

% ------------------------------------------------------------------ local --

    function [J, g, R] = cvodes_cost(p)
        F = ode(ODEFcn = @(tt, yy) prob_mod_dynamics_LV(tt, yy, p), ...
            InitialValue = y0, InitialTime = times(1));
        F.Solver = 'cvodesstiff';
        F.RelativeTolerance = 1e-6;
        F.AbsoluteTolerance = 1e-8;
        S = solve(F, times);
        ysim = S.Solution.'; % ntimes x nstates
        Rm = (ysim(:, observed_idx) - observed_data) .* weight;
        R = Rm(:);
        J = sum(R .^ 2);
        g = 0;
    end

    function [J, g, R] = tcp_cost(t_, p)
        writeline(t_, sprintf('%.17g ', p));
        reply = readline(t_);
        vals = sscanf(reply, '%f');
        if isempty(vals) || isnan(vals(1))
            J = 1e20; R = 1e10 * ones(62, 1); g = 0; % failed integration penalty
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

    function res = run_meigo(cost, x0, lb_, ub_, maxeval_, seed_)
        problem.f = cost;
        problem.x_L = lb_;
        problem.x_U = ub_;
        problem.x_0 = x0;
        mopts = opts.meigo;
        mopts.maxeval = maxeval_;
        mopts.iterprint = 0;
        if isfield(mopts, 'refit'), mopts = rmfield(mopts, 'refit'); end
        rng(seed_, 'twister');
        res = MEIGO(problem, mopts, 'ESS');
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
