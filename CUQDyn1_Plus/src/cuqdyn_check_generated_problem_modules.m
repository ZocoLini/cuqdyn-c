function report = cuqdyn_check_generated_problem_modules(problem, legacyDir, generatedDir, varargin)
%CUQDYN_CHECK_GENERATED_PROBLEM_MODULES Compare generated modules to legacy files.
%
% report = cuqdyn_check_generated_problem_modules(problem, legacyDir,
% generatedDir) generates legacy-compatible dynamics/cost files, places the
% generated directory first on the MATLAB path, and verifies that the legacy
% and generated modules produce the same dynamics, cost, and residuals.

opts = parseOptions(varargin{:});
problem = cuqdyn_validate_problem(problem);

if isstring(legacyDir), legacyDir = char(legacyDir); end
if isstring(generatedDir), generatedDir = char(generatedDir); end

cuqdyn_generate_problem_files(problem, generatedDir, 'Overwrite', true);

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(repoRoot));

dynName = sprintf('prob_mod_dynamics_%s', char(problem.name));
costName = sprintf('prob_mod_cost_%s', char(problem.name));

nStates = numel(problem.states);
nParams = numel(problem.parameters);
p = getVectorField(problem, 'true_parameters', nParams, linspace(0.2, 1.1, nParams)');
y = getVectorField(problem, 'test_state', nStates, linspace(0.4, 1.3, nStates)');
yComplex = y + 1i * (1e-20 ./ (1:nStates)');
y0 = getVectorField(problem, 'test_initial_values', nStates, y);
observedIdx = getObservedIdx(problem, nStates);
texp = getVectorField(problem, 'test_times', [], linspace(0, opts.TFinal, opts.NTimes)');
texp = texp(:);

removePathIfPresent(generatedDir);
addpath(legacyDir, '-begin');
clear(dynName, costName);
legacyDynHandle = str2func(dynName);
legacyCostHandle = str2func(costName);
legacyDynFile = which(dynName);
legacyCostFile = which(costName);

[odeOptions, ~] = cuqdyn_get_ode_options();
legacyDy = legacyDynHandle(0, y, p);
legacyDyComplex = legacyDynHandle(0, yComplex, p);
[~, yfull] = ode15s(@(t, yy) legacyDynHandle(t, yy, p), texp, y0, odeOptions);
yexp = yfull(:, observedIdx) + opts.DataOffset;
costOpts = struct('residual_model', 'known_sigma', ...
    'sigma', repmat(opts.Sigma, 1, numel(observedIdx)), ...
    'sigma_is_known', true);
[legacyJ, legacyG, legacyR] = legacyCostHandle( ...
    p, texp, yexp, observedIdx, legacyDynHandle, y0, odeOptions, costOpts);

rmpath(legacyDir);
addpath(generatedDir, '-begin');
clear(dynName, costName);
generatedDynHandle = str2func(dynName);
generatedCostHandle = str2func(costName);
generatedDynFile = which(dynName);
generatedCostFile = which(costName);

generatedDy = generatedDynHandle(0, y, p);
generatedDyComplex = generatedDynHandle(0, yComplex, p);
[generatedJ, generatedG, generatedR] = generatedCostHandle( ...
    p, texp, yexp, observedIdx, generatedDynHandle, y0, odeOptions, costOpts);

removePathIfPresent(generatedDir);
addpath(legacyDir, '-begin');
clear(dynName, costName);

report = struct();
report.problem = problem.name;
report.legacyDynamicsFile = string(legacyDynFile);
report.generatedDynamicsFile = string(generatedDynFile);
report.legacyCostFile = string(legacyCostFile);
report.generatedCostFile = string(generatedCostFile);
report.maxDynamicsDifference = max(abs(legacyDy(:) - generatedDy(:)));
report.maxComplexDynamicsDifference = max(abs(legacyDyComplex(:) - generatedDyComplex(:)));
report.costDifference = abs(legacyJ - generatedJ);
report.gradientDifference = abs(legacyG - generatedG);
report.maxResidualDifference = max(abs(legacyR(:) - generatedR(:)));
report.passed = report.maxDynamicsDifference < opts.Tolerance && ...
    report.maxComplexDynamicsDifference < opts.Tolerance && ...
    report.costDifference < opts.Tolerance && ...
    report.gradientDifference < opts.Tolerance && ...
    report.maxResidualDifference < opts.Tolerance;

if ~report.passed
    error('cuqdyn_check_generated_problem_modules:Mismatch', ...
        'Generated modules for %s do not match legacy modules.', problem.name);
end

fprintf('Generated %s dynamics and cost match the legacy files.\n', problem.name);
end

function opts = parseOptions(varargin)
opts = struct();
opts.Tolerance = 1e-10;
opts.TFinal = 0.5;
opts.NTimes = 5;
opts.DataOffset = 0.01;
opts.Sigma = 0.1;

if mod(numel(varargin), 2) ~= 0
    error('cuqdyn_check_generated_problem_modules:InvalidInputs', ...
        'Options must be supplied as name-value pairs.');
end

for i = 1:2:numel(varargin)
    name = validatestring(varargin{i}, ...
        {'Tolerance', 'TFinal', 'NTimes', 'DataOffset', 'Sigma'});
    opts.(name) = varargin{i+1};
end
end

function value = getVectorField(problem, fieldName, expectedCount, defaultValue)
if isfield(problem, fieldName) && ~isempty(problem.(fieldName))
    value = problem.(fieldName);
else
    value = defaultValue;
end

if isrow(value)
    value = value(:);
end
if ~isempty(expectedCount) && numel(value) ~= expectedCount
    error('cuqdyn_check_generated_problem_modules:InvalidVectorSize', ...
        '%s must contain %d value(s).', fieldName, expectedCount);
end
end

function observedIdx = getObservedIdx(problem, nStates)
if isfield(problem, 'observed_state_indices') && ~isempty(problem.observed_state_indices)
    observedIdx = problem.observed_state_indices(:)';
elseif isfield(problem, 'observed_states') && ~isempty(problem.observed_states)
    [~, observedIdx] = ismember(problem.observed_states, problem.states);
else
    observedIdx = 1:nStates;
end
end

function removePathIfPresent(folderPath)
if contains(path, folderPath)
    rmpath(folderPath);
end
end
