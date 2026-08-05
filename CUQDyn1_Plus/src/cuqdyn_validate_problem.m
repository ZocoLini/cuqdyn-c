function problem = cuqdyn_validate_problem(problem)
%CUQDYN_VALIDATE_PROBLEM Validate and normalize a high-level CUQDyn problem.
%
% problem = cuqdyn_validate_problem(problem) checks the high-level schema used
% by define_problem_<Name>.m files and normalizes text fields to MATLAB string
% vectors. It preserves optional metadata but validates fields that affect
% generation, fitting, residual weighting, and synthetic-data workflows.
%
% Required fields:
%   name        string/char scalar used in generated function names
%   states      string/cellstr vector of state variable names
%   parameters  string/cellstr vector of parameter variable names
%   odes        string/cellstr vector, one right-hand side per state
%
% Optional checked fields include observed_states, initial_values,
% parameter_bounds, and cost declarations. Synthetic-data fields are validated
% by cuqdyn_generate_synthetic_data because they are only required for data
% generation workflows.

if nargin ~= 1 || ~isstruct(problem) || numel(problem) ~= 1
    error('cuqdyn_validate_problem:InvalidProblem', ...
        'Problem must be a scalar struct.');
end

requiredFields = {'name', 'states', 'parameters', 'odes'};
for i = 1:numel(requiredFields)
    if ~isfield(problem, requiredFields{i})
        error('cuqdyn_validate_problem:MissingField', ...
            'Problem is missing required field "%s".', requiredFields{i});
    end
end

problem.name = normalizeScalarText(problem.name, 'name');
problem.states = normalizeTextVector(problem.states, 'states');
problem.parameters = normalizeTextVector(problem.parameters, 'parameters');
problem.odes = normalizeTextVector(problem.odes, 'odes');

if ~isvarname(char(problem.name))
    error('cuqdyn_validate_problem:InvalidName', ...
        'Problem name "%s" must be a valid MATLAB identifier.', problem.name);
end

validateIdentifiers(problem.states, 'state');
validateIdentifiers(problem.parameters, 'parameter');

if numel(unique(problem.states)) ~= numel(problem.states)
    error('cuqdyn_validate_problem:DuplicateStates', ...
        'State names must be unique.');
end
if numel(unique(problem.parameters)) ~= numel(problem.parameters)
    error('cuqdyn_validate_problem:DuplicateParameters', ...
        'Parameter names must be unique.');
end
if any(ismember(problem.states, problem.parameters))
    error('cuqdyn_validate_problem:NameCollision', ...
        'State and parameter names must not overlap.');
end

nStates = numel(problem.states);
nParams = numel(problem.parameters);
if numel(problem.odes) ~= nStates
    error('cuqdyn_validate_problem:OdeCountMismatch', ...
        'Problem has %d states but %d ODE expressions.', nStates, numel(problem.odes));
end
if any(strlength(problem.odes) == 0)
    error('cuqdyn_validate_problem:EmptyOde', ...
        'ODE expressions must be non-empty.');
end

if isfield(problem, 'observed_states') && ~isempty(problem.observed_states)
    problem.observed_states = normalizeTextVector(problem.observed_states, 'observed_states');
    missing = setdiff(problem.observed_states, problem.states);
    if ~isempty(missing)
        error('cuqdyn_validate_problem:UnknownObservedState', ...
            'Unknown observed state(s): %s.', strjoin(cellstr(missing), ', '));
    end
end

if isfield(problem, 'initial_values') && ~isempty(problem.initial_values)
    if ~isnumeric(problem.initial_values) || numel(problem.initial_values) ~= nStates
        error('cuqdyn_validate_problem:InitialValueSize', ...
            'initial_values must be numeric with one value per state.');
    end
    problem.initial_values = problem.initial_values(:);
end

if isfield(problem, 'parameter_bounds') && ~isempty(problem.parameter_bounds)
    bounds = problem.parameter_bounds;
    if ~isstruct(bounds) || ~isfield(bounds, 'lower') || ~isfield(bounds, 'upper')
        error('cuqdyn_validate_problem:InvalidBounds', ...
            'parameter_bounds must contain lower and upper numeric vectors.');
    end
    if ~isnumeric(bounds.lower) || ~isnumeric(bounds.upper) || ...
            numel(bounds.lower) ~= nParams || numel(bounds.upper) ~= nParams
        error('cuqdyn_validate_problem:BoundSize', ...
            'parameter_bounds.lower and .upper must have one value per parameter.');
    end
    if any(bounds.lower(:) > bounds.upper(:))
        error('cuqdyn_validate_problem:InvalidBoundOrder', ...
            'parameter_bounds.lower must be <= parameter_bounds.upper.');
    end
    problem.parameter_bounds.lower = bounds.lower(:);
    problem.parameter_bounds.upper = bounds.upper(:);
end

if isfield(problem, 'cost') && ~isempty(problem.cost)
    problem.cost = validateCost(problem.cost);
end
end

function txt = normalizeScalarText(value, fieldName)
txt = normalizeTextVector(value, fieldName);
if numel(txt) ~= 1
    error('cuqdyn_validate_problem:InvalidTextScalar', ...
        '%s must be a text scalar.', fieldName);
end
txt = txt(1);
end

function txt = normalizeTextVector(value, fieldName)
if ischar(value)
    txt = string(cellstr(value));
elseif isstring(value)
    txt = value(:);
elseif iscellstr(value)
    txt = string(value(:));
else
    error('cuqdyn_validate_problem:InvalidTextVector', ...
        '%s must be a string, char, or cellstr value.', fieldName);
end

if any(ismissing(txt)) || any(strlength(strtrim(txt)) == 0)
    error('cuqdyn_validate_problem:EmptyText', ...
        '%s must not contain empty text.', fieldName);
end
txt = strtrim(txt);
end

function validateIdentifiers(names, label)
for i = 1:numel(names)
    if ~isvarname(char(names(i)))
        error('cuqdyn_validate_problem:InvalidIdentifier', ...
            '%s name "%s" must be a valid MATLAB identifier.', label, names(i));
    end
end
end

function cost = validateCost(cost)
if ~isstruct(cost) || numel(cost) ~= 1
    error('cuqdyn_validate_problem:InvalidCost', ...
        'problem.cost must be a scalar struct.');
end

if isfield(cost, 'residual_model') && ~isempty(cost.residual_model)
    residualModel = validatestring(char(cost.residual_model), ...
        {'none', 'known_sigma', 'state_weights'});
    cost.residual_model = string(residualModel);
else
    cost.residual_model = "none";
end

if isfield(cost, 'sigma_mode') && ~isempty(cost.sigma_mode)
    sigmaMode = validatestring(char(cost.sigma_mode), ...
        {'explicit', 'from_reference_trajectory_mean'});
    cost.sigma_mode = string(sigmaMode);
end

if isfield(cost, 'sigma') && ~isempty(cost.sigma)
    if ~isnumeric(cost.sigma) || any(~isfinite(cost.sigma(:))) || any(cost.sigma(:) <= 0)
        error('cuqdyn_validate_problem:InvalidSigma', ...
            'problem.cost.sigma must contain positive finite values.');
    end
    cost.sigma = cost.sigma(:)';
end

if isfield(cost, 'observed_state_weights') && ~isempty(cost.observed_state_weights)
    if ~isnumeric(cost.observed_state_weights) || ...
            any(~isfinite(cost.observed_state_weights(:)))
        error('cuqdyn_validate_problem:InvalidStateWeights', ...
            'problem.cost.observed_state_weights must contain finite numeric values.');
    end
    cost.observed_state_weights = cost.observed_state_weights(:)';
end

if isfield(cost, 'noise_percent') && ~isempty(cost.noise_percent)
    if ~isscalar(cost.noise_percent) || ~isnumeric(cost.noise_percent) || ...
            ~isfinite(cost.noise_percent) || cost.noise_percent < 0
        error('cuqdyn_validate_problem:InvalidNoisePercent', ...
            'problem.cost.noise_percent must be a nonnegative finite scalar.');
    end
end
end
