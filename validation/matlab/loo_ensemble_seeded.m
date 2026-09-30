function ens = loo_ensemble_seeded(pb, base_seed, trace_dir)
%LOO_ENSEMBLE_SEEDED The published cuq_loo_ensemble, sequential and seeded per launch.
%
% Copy of CUQDyn1_Plus/src/private/cuq_loo_ensemble.m reduced to what layer 5
% needs: the full fit and the m-1 global refits (the Plus default strategy),
% run sequentially, each MEIGO launch k preceded by rng(base_seed + k), every
% cost evaluation recorded to trace_dir/evals_<k>.txt and the result to
% trace_dir/theta_<k>.txt - the same trace the C side writes. Refits start from
% the problem guess, as in the published code. The trace is kept in memory
% during a launch because MEIGO closes every open file while it runs.

opts = cuqdyn_fill_meigo_options(pb.meigo_opts, pb.n_params);
cost_opts = cuqdyn_fill_cost_options(opts.cost_opts);
for f = {'cost_opts', 'refit', 'fim', 'parallel'}
    if isfield(opts, f{1}), opts = rmfield(opts, f{1}); end
end
ode_opts = pb.ode_opts;
times = pb.times; observed_data = pb.observed_data; observed_idx = pb.observed_idx;
y0 = pb.y0; m = pb.m; nstates = pb.nstates; dynamics = pb.dynamics;
if ~exist(trace_dir, 'dir'), mkdir(trace_dir); end

problem.f = @recorded_cost;
problem.x_L = pb.lb_params;
problem.x_U = pb.ub_params;
problem.x_0 = pb.guess_params;

trace = zeros(0, pb.n_params + 1);
rng(base_seed, 'twister');
fprintf('launch 0 (seed %d): full fit\n', base_seed);
Results_tot = MEIGO(problem, opts, 'ESS', times, observed_data, observed_idx, dynamics, y0, ode_opts, cost_opts);
flush_trace(0, Results_tot.xbest, Results_tot.fbest);
parameters_init = Results_tot.xbest;

sol_full = ODE_solve(y0, times, parameters_init, dynamics, ode_opts);
media_tot = sol_full(:, 2:end);

media_matrix = NaN(m, nstates, m - 1);
resid_loo = NaN(m - 1, numel(observed_idx));
loo_params = NaN(m - 1, pb.n_params);
for i = 2:m
    k = i - 1;
    t_loo = times([1:i-1, i+1:end]);
    y_loo = observed_data([1:i-1, i+1:end], :);
    trace = zeros(0, pb.n_params + 1);
    rng(base_seed + k, 'twister');
    fprintf('launch %d (seed %d): leave out t(%d)\n', k, base_seed + k, i);
    res = MEIGO(problem, opts, 'ESS', t_loo, y_loo, observed_idx, dynamics, y0, ode_opts, cost_opts);
    flush_trace(k, res.xbest, res.fbest);
    params_loo = res.xbest;
    sol = ODE_solve(y0, times, params_loo, dynamics, ode_opts);
    media_matrix(:, :, i - 1) = sol(:, 2:end);
    resid_loo(i - 1, :) = abs(observed_data(i, :) - sol(i, observed_idx + 1));
    loo_params(i - 1, :) = params_loo;
end

UQ_lower_obs = NaN(m, numel(observed_idx));
UQ_upper_obs = NaN(m, numel(observed_idx));
UQ_lower_obs(1, :) = observed_data(1, :);
UQ_upper_obs(1, :) = observed_data(1, :);
for j = 1:numel(observed_idx)
    state_idx = observed_idx(j);
    for i = 2:m
        e = squeeze(media_matrix(i, state_idx, :));
        r = resid_loo(:, j);
        UQ_lower_obs(i, j) = quantile(e - r, pb.alp);
        UQ_upper_obs(i, j) = quantile(e + r, 1 - pb.alp);
    end
end

ens = struct('parameters_init', parameters_init, 'media_tot', media_tot, ...
    'media_matrix', media_matrix, 'resid_loo', resid_loo, 'loo_params', loo_params, ...
    'UQ_lower_obs', UQ_lower_obs, 'UQ_upper_obs', UQ_upper_obs, 'm', m);

    function [J, g, R] = recorded_cost(x, varargin)
        [J, g, R] = pb.cost(x, varargin{:});
        trace(end + 1, :) = [x(:).' J]; %#ok<AGROW>
    end
    function flush_trace(kk, theta, J)
        write_trace(fullfile(trace_dir, sprintf('evals_%d.txt', kk)), trace);
        write_trace(fullfile(trace_dir, sprintf('theta_%d.txt', kk)), [theta(:).' J]);
    end
end
