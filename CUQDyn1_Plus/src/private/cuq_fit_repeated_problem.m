function [params, info] = cuq_fit_repeated_problem(problem, meigo_opts, ...
    t_fit, y_fit, observed_idx, dynamics_handle, initial_values, ...
    ode_opts, cost_opts, seed_params, lb_params, ub_params, refit_opts)
%CUQ_FIT_REPEATED_PROBLEM Fit one repeated problem for the LOO ensemble.

info = default_info(refit_opts.strategy);

switch refit_opts.strategy
    case 'global'
        [params, info] = fit_global(problem, meigo_opts, t_fit, y_fit, ...
            observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts, info);

    case 'local_after_global'
        [params, info] = fit_local_guarded(problem, meigo_opts, t_fit, y_fit, ...
            observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts, ...
            seed_params, lb_params, ub_params, refit_opts, info);

    otherwise
        error('cuq_fit_repeated_problem:UnknownStrategy', ...
            'Unknown refit strategy: %s', refit_opts.strategy);
end

end

function info = default_info(strategy)
info = struct();
info.strategy = strategy;
info.method = '';
info.local_exitflag = NaN;
info.local_cost = NaN;
info.seed_cost = NaN;
info.final_cost = NaN;
info.used_global_fallback = false;
info.local_failed = false;
info.bound_hit = false;
info.large_parameter_move = false;
info.message = '';
end

function [params, info] = fit_global(problem, meigo_opts, t_fit, y_fit, ...
    observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts, info)

Results = MEIGO(problem, meigo_opts, 'ESS', t_fit, y_fit, observed_idx, ...
    dynamics_handle, initial_values, ode_opts, cost_opts);
params = Results.xbest;
info.method = 'global';
info.final_cost = local_cost(problem.f, params, t_fit, y_fit, observed_idx, ...
    dynamics_handle, initial_values, ode_opts, cost_opts);
end

function [params, info] = fit_local_guarded(problem, meigo_opts, t_fit, y_fit, ...
    observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts, ...
    seed_params, lb_params, ub_params, refit_opts, info)

if exist('lsqnonlin', 'file') ~= 2
    info.local_failed = true;
    info.message = 'lsqnonlin unavailable; used global fallback';
    [params, info] = fallback_global(problem, meigo_opts, t_fit, y_fit, ...
        observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts, info);
    return;
end

seed_params = seed_params(:)';
lb_params = lb_params(:)';
ub_params = ub_params(:)';
log_idx = [];
if isfield(meigo_opts, 'log_var') && ~isempty(meigo_opts.log_var)
    log_idx = meigo_opts.log_var(:)';
end
log_idx = log_idx(log_idx >= 1 & log_idx <= numel(seed_params));

z0 = encode_params(seed_params, log_idx);
zL = encode_params(lb_params, log_idx);
zU = encode_params(ub_params, log_idx);
maxeval = ceil(numel(seed_params) * refit_opts.local_maxeval_factor);

residual_fun = @(z) local_residuals(problem.f, decode_params(z, log_idx), ...
    t_fit, y_fit, observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts);
info.seed_cost = sum(residual_fun(z0).^2);

try
    local_opts = optimoptions('lsqnonlin', ...
        'Display', 'off', ...
        'MaxFunctionEvaluations', maxeval, ...
        'MaxIterations', max(20, maxeval), ...
        'FunctionTolerance', 1e-8, ...
        'StepTolerance', 1e-8);
    [zbest, resnorm, ~, exitflag] = lsqnonlin(residual_fun, z0, zL, zU, local_opts);
    local_params = decode_params(zbest, log_idx);
    info.local_exitflag = exitflag;
    info.local_cost = resnorm;
catch ME
    local_params = seed_params;
    info.local_exitflag = -999;
    info.local_cost = Inf;
    info.local_failed = true;
    info.message = ME.message;
end

if ~(info.local_exitflag > 0) || ~isfinite(info.local_cost)
    info.local_failed = true;
end
if isfinite(info.seed_cost) && info.local_cost > refit_opts.max_cost_ratio_from_start * max(info.seed_cost, eps)
    info.local_failed = true;
end
info.bound_hit = is_near_bound(local_params, lb_params, ub_params, refit_opts.bound_tol);
info.large_parameter_move = has_large_fold_change(local_params, seed_params, ...
    refit_opts.max_parameter_fold_change);

needsFallback = info.local_failed || info.large_parameter_move || ...
    (refit_opts.retry_global_on_bound_hit && info.bound_hit);
if needsFallback && refit_opts.retry_global_on_failure
    [params, info] = fallback_global(problem, meigo_opts, t_fit, y_fit, ...
        observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts, info);
else
    params = local_params;
    info.method = 'local';
    info.final_cost = info.local_cost;
end
end

function [params, info] = fallback_global(problem, meigo_opts, t_fit, y_fit, ...
    observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts, info)
info.used_global_fallback = true;
Results = MEIGO(problem, meigo_opts, 'ESS', t_fit, y_fit, observed_idx, ...
    dynamics_handle, initial_values, ode_opts, cost_opts);
params = Results.xbest;
info.method = 'global_fallback';
info.final_cost = local_cost(problem.f, params, t_fit, y_fit, observed_idx, ...
    dynamics_handle, initial_values, ode_opts, cost_opts);
end

function R = local_residuals(cost_handle, x, t_fit, y_fit, observed_idx, ...
    dynamics_handle, initial_values, ode_opts, cost_opts)
[J, ~, R] = cost_handle(x, t_fit, y_fit, observed_idx, dynamics_handle, ...
    initial_values, ode_opts, cost_opts);
if isempty(R)
    R = sqrt(max(J, 0));
end
R = R(:);
R(~isfinite(R)) = 1e100;
end

function J = local_cost(cost_handle, x, t_fit, y_fit, observed_idx, ...
    dynamics_handle, initial_values, ode_opts, cost_opts)
[J, ~, R] = cost_handle(x, t_fit, y_fit, observed_idx, dynamics_handle, ...
    initial_values, ode_opts, cost_opts);
if isempty(J) || ~isfinite(J)
    J = sum(R(:).^2);
end
end

function z = encode_params(x, log_idx)
z = x(:)';
if ~isempty(log_idx)
    z(log_idx) = log(max(z(log_idx), realmin));
end
end

function x = decode_params(z, log_idx)
x = z(:)';
if ~isempty(log_idx)
    x(log_idx) = exp(x(log_idx));
end
end

function tf = is_near_bound(x, lb, ub, tol)
scale = max(abs(ub - lb), eps);
tf = any((x - lb) ./ scale <= tol | (ub - x) ./ scale <= tol);
end

function tf = has_large_fold_change(x, seed, max_fold)
den = max(abs(seed), realmin);
ratio = abs(x) ./ den;
tf = any(ratio > max_fold | ratio < 1/max_fold);
end
