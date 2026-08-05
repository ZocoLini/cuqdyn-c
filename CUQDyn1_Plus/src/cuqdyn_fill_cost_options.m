function cost_opts = cuqdyn_fill_cost_options(cost_opts)
%CUQDYN_FILL_COST_OPTIONS Fill missing residual weighting options.

if nargin < 1 || isempty(cost_opts)
    cost_opts = struct();
end

defaults = cuqdyn_default_options(1).cost;
if ~isfield(defaults, 'observed_state_weights')
    defaults.observed_state_weights = [];
end
cost_opts = local_merge(defaults, cost_opts);

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
