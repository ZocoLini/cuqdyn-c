function meigo_server(model, port, base_seed, trace_dir)
%MEIGO_SERVER Run MEIGO for every launch the C pipeline asks for.
%
%   meigo_server('lv2', 45602, 20260917, 'validation/layer5/c/lv2')
%
% Connects to pipeline_meigo (which must already be listening), then for each
% "optimize k n m_fit" line seeds rng with base_seed + k, runs MEIGO/eSS on the
% shared problem definition with a cost that is evaluated by the C side, and
% replies "done theta J". Every evaluation goes to trace_dir/evals_<k>.txt and
% the result to trace_dir/theta_<k>.txt, in the same format the C side writes,
% so compare_lockstep.py can diff them. The trace is kept in memory during the
% launch because MEIGO closes every open file while it runs.

pb = problem_def(model);
if ~exist(trace_dir, 'dir'), mkdir(trace_dir); end

t = [];
for attempt = 1:60
    try
        t = tcpclient('127.0.0.1', port, 'Timeout', 3600);
        break;
    catch
        pause(1);
    end
end
if isempty(t), error('meigo_server:connect', 'pipeline_meigo not listening on %d', port); end
configureTerminator(t, 'LF');

mopts = cuqdyn_fill_meigo_options(pb.meigo_opts, pb.n_params);
for f = {'cost_opts', 'refit', 'fim', 'parallel'}
    if isfield(mopts, f{1}), mopts = rmfield(mopts, f{1}); end
end
problem.x_L = pb.lb_params;
problem.x_U = pb.ub_params;
problem.x_0 = pb.guess_params;
problem.f = @served_cost;

trace = zeros(0, pb.n_params + 1);
while true
    line = char(readline(t));
    if startsWith(line, 'quit'), break; end
    tok = sscanf(line, 'optimize %d %d %d');
    if numel(tok) ~= 3, error('meigo_server:protocol', 'unexpected line: %s', line); end
    k = tok(1); n = tok(2);
    if n ~= pb.n_params
        error('meigo_server:protocol', 'C declares %d parameters, problem has %d', n, pb.n_params);
    end
    trace = zeros(0, pb.n_params + 1);
    rng(base_seed + k, 'twister');
    fprintf('launch %d (seed %d)\n', k, base_seed + k);
    res = MEIGO(problem, mopts, 'ESS');
    write_trace(fullfile(trace_dir, sprintf('evals_%d.txt', k)), trace);
    write_trace(fullfile(trace_dir, sprintf('theta_%d.txt', k)), [res.xbest(:).' res.fbest]);
    writeline(t, ['done ' sprintf('%.17g ', res.xbest) sprintf('%.17g', res.fbest)]);
end
clear t
fprintf('meigo_server: done\n');

    function [J, g, R] = served_cost(x, varargin)
        writeline(t, ['eval ' sprintf('%.17g ', x)]);
        vals = sscanf(char(readline(t)), '%f');
        J = vals(1);
        R = vals(2:end);
        g = 0;
        trace(end + 1, :) = [x(:).' J]; %#ok<AGROW>
    end
end
