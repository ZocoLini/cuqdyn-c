function fim_opts = cuqdyn_fill_fim_options(fim_opts, n_params)
%CUQDYN_FILL_FIM_OPTIONS Fill FIM covariance options from defaults.

if nargin < 1 || isempty(fim_opts)
    fim_opts = struct();
end
if nargin < 2 || isempty(n_params)
    n_params = 1;
end

defaults = cuqdyn_default_options(n_params).fim;
fim_opts = local_merge(defaults, fim_opts);

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
