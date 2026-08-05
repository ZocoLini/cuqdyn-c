function [ode_options, ode_opts] = cuqdyn_get_ode_options()
%CUQDYN_GET_ODE_OPTIONS Return odeset options from CUQDyn defaults.

default_opts = cuqdyn_default_options(1).ode;

if isappdata(0, 'CUQDyn_ODE_Options')
    ode_opts = getappdata(0, 'CUQDyn_ODE_Options');
else
    ode_opts = default_opts;
end

ode_opts = local_merge(default_opts, ode_opts);

ode_options = cuqdyn_odeset_from_options(ode_opts);

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
