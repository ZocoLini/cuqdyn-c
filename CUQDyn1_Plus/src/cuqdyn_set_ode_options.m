function cuqdyn_set_ode_options(ode_opts)
%CUQDYN_SET_ODE_OPTIONS Set process-wide ODE options for CUQDyn examples.
%
% The setting is intentionally lightweight: examples can set it before
% calling CUQDyn1_Plus, and ODE_solve plus model cost functions will use it.

if nargin < 1 || isempty(ode_opts)
    ode_opts = cuqdyn_default_options(1).ode;
end

setappdata(0, 'CUQDyn_ODE_Options', ode_opts);

end
