function refit_opts = cuqdyn_fill_refit_options(refit_opts, n_params)
%CUQDYN_FILL_REFIT_OPTIONS Fill guarded repeated-refit options.

if nargin < 1 || isempty(refit_opts)
    refit_opts = struct();
end
if nargin < 2 || isempty(n_params)
    n_params = 1;
end

defaults = cuqdyn_default_options(n_params);
refit_opts = local_merge(defaults.meigo.refit, refit_opts);

refit_opts.strategy = lower(char(refit_opts.strategy));
refit_opts.local_solver = lower(char(refit_opts.local_solver));

validStrategies = {'global', 'local_after_global'};
if ~ismember(refit_opts.strategy, validStrategies)
    error('cuqdyn_fill_refit_options:UnknownStrategy', ...
        'Unknown refit strategy: %s', refit_opts.strategy);
end

if ~strcmp(refit_opts.local_solver, 'lsqnonlin')
    error('cuqdyn_fill_refit_options:UnsupportedLocalSolver', ...
        'Only lsqnonlin is currently supported for guarded local refits.');
end

refit_opts.local_maxeval_factor = max(1, double(refit_opts.local_maxeval_factor));
refit_opts.max_cost_ratio_from_start = max(1, double(refit_opts.max_cost_ratio_from_start));
refit_opts.max_parameter_fold_change = max(1, double(refit_opts.max_parameter_fold_change));
refit_opts.bound_tol = max(0, double(refit_opts.bound_tol));
refit_opts.retry_global_on_failure = logical(refit_opts.retry_global_on_failure);
refit_opts.retry_global_on_bound_hit = logical(refit_opts.retry_global_on_bound_hit);

end

function out = local_merge(base, override)
out = base;
fields = fieldnames(override);
for i = 1:numel(fields)
    f = fields{i};
    if isstruct(override.(f)) && isfield(out, f) && isstruct(out.(f))
        out.(f) = local_merge(out.(f), override.(f));
    else
        out.(f) = override.(f);
    end
end
end
