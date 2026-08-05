function [ode_options, ode_solver] = cuqdyn_odeset_from_options(ode_opts)
%CUQDYN_ODESET_FROM_OPTIONS Convert CUQDyn ODE option struct to odeset.
%
%   [ode_options, ode_solver] = cuqdyn_odeset_from_options(ode_opts)
%   returns the odeset options and the ODE solver function handle requested
%   by ode_opts.solver. Existing callers that request one output receive only
%   the odeset options.

defaults = cuqdyn_default_options(1).ode;
if nargin < 1 || isempty(ode_opts)
    ode_opts = defaults;
else
    ode_opts = local_merge(defaults, ode_opts);
end

ode_solver = local_solver_handle(ode_opts.solver);

args = {'RelTol', ode_opts.RelTol, 'AbsTol', ode_opts.AbsTol};
if isfield(ode_opts, 'NonNegative') && ~isempty(ode_opts.NonNegative)
    args = [args, {'NonNegative', ode_opts.NonNegative}];
end
ode_options = odeset(args{:});

end

function solver = local_solver_handle(solverSpec)
if isempty(solverSpec)
    error('cuqdyn_odeset_from_options:EmptySolver', ...
        'ode.solver must be a solver name or function handle.');
end

if isa(solverSpec, 'function_handle')
    solver = solverSpec;
    return
end

if isstring(solverSpec)
    if ~isscalar(solverSpec)
        error('cuqdyn_odeset_from_options:InvalidSolver', ...
            'ode.solver must be a scalar string, char vector, or function handle.');
    end
    solverSpec = char(solverSpec);
elseif ~ischar(solverSpec)
    error('cuqdyn_odeset_from_options:InvalidSolver', ...
        'ode.solver must be a scalar string, char vector, or function handle.');
end

if exist(solverSpec, 'file') ~= 2 && exist(solverSpec, 'builtin') ~= 5
    error('cuqdyn_odeset_from_options:UnknownSolver', ...
        'ODE solver "%s" was not found on the MATLAB path.', solverSpec);
end

solver = str2func(solverSpec);
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
