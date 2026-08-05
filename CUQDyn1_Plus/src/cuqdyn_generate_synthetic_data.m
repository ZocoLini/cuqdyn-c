function out = cuqdyn_generate_synthetic_data(problem, varargin)
%CUQDYN_GENERATE_SYNTHETIC_DATA Generate CUQDyn-formatted synthetic CSV data.
%
% out = cuqdyn_generate_synthetic_data(problem) uses problem.synthetic_data to
% simulate the model, add observation noise to observed states after t=0, set
% hidden states to NaN after t=0, validate nonnegative finite values, and write
% a CSV compatible with loadStateData.
%
% The CSV convention is:
%   column 1     time
%   columns 2:N all model states in problem.states order
%   row 1        finite initial values for every state
%   rows 2:end   finite values for observed states and NaN for hidden states
%
% Name-value options:
%   'BaseDir'        base folder for relative output_folder declarations.
%   'DynamicsHandle' generated or legacy dynamics function handle.

opts = parseOptions(varargin{:});
problem = cuqdyn_validate_problem(problem);
synthetic = validateSyntheticDataSpec(problem);

baseDir = opts.BaseDir;
if isempty(baseDir)
    baseDir = pwd;
end
if isstring(baseDir), baseDir = char(baseDir); end

dynamicsHandle = opts.DynamicsHandle;
if isempty(dynamicsHandle)
    dynamicsHandle = str2func(sprintf('prob_mod_dynamics_%s', char(problem.name)));
end

timePoints = synthetic.times(:);
trueParameters = synthetic.true_parameters(:)';
initialValues = synthetic.initial_values(:)';
observedIdx = synthetic.observed_state_indices(:)';
isObserved = false(1, numel(problem.states));
isObserved(observedIdx) = true;

if isfield(synthetic, 'rng_seed') && ~isempty(synthetic.rng_seed)
    rng(synthetic.rng_seed);
end

odeOpts = getOdeOptions(synthetic);
[T, Y_true] = ode15s(@(t, y) dynamicsHandle(t, y, trueParameters), ...
    timePoints, initialValues, odeOpts);

[Y_data, sigma] = applyNoise(Y_true, observedIdx, synthetic);
Y_data(2:end, ~isObserved) = NaN;
assertNoNegativeFiniteData(Y_data, synthetic.output_file);

outputFolder = char(synthetic.output_folder);
if ~isAbsolutePath(outputFolder)
    outputFolder = fullfile(baseDir, outputFolder);
end
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end
outputCsv = fullfile(outputFolder, char(synthetic.output_file));

headers = [{'time'}, arrayfun(@(j) sprintf('y%d', j), 1:size(Y_data, 2), ...
    'UniformOutput', false)];
writetable(array2table([T, Y_data], 'VariableNames', headers), outputCsv);

if synthetic.make_plots
    plotSyntheticData(T, Y_true, Y_data, isObserved, char(problem.name));
end

fprintf('Generated %s\n', outputCsv);
fprintf('Observed state indices: %s\n', mat2str(observedIdx));
fprintf('Noise model: %s\n', char(synthetic.noise_model));

out = struct();
out.outputCsv = string(outputCsv);
out.times = T;
out.Y_true = Y_true;
out.Y_data = Y_data;
out.observed_idx = observedIdx;
out.sigma = sigma;
end

function opts = parseOptions(varargin)
opts = struct();
opts.BaseDir = '';
opts.DynamicsHandle = [];

if mod(numel(varargin), 2) ~= 0
    error('cuqdyn_generate_synthetic_data:InvalidInputs', ...
        'Options must be supplied as name-value pairs.');
end

for i = 1:2:numel(varargin)
    name = validatestring(varargin{i}, {'BaseDir', 'DynamicsHandle'});
    opts.(name) = varargin{i+1};
end
end

function synthetic = validateSyntheticDataSpec(problem)
if ~isfield(problem, 'synthetic_data') || isempty(problem.synthetic_data)
    error('cuqdyn_generate_synthetic_data:MissingSyntheticData', ...
        'problem.synthetic_data is required to generate synthetic data.');
end

synthetic = problem.synthetic_data;
requiredFields = {'times', 'initial_values', 'true_parameters', ...
    'observed_state_indices', 'output_folder', 'output_file'};
for i = 1:numel(requiredFields)
    if ~isfield(synthetic, requiredFields{i}) || isempty(synthetic.(requiredFields{i}))
        error('cuqdyn_generate_synthetic_data:MissingField', ...
            'problem.synthetic_data.%s is required.', requiredFields{i});
    end
end

nStates = numel(problem.states);
nParams = numel(problem.parameters);
if ~isnumeric(synthetic.times) || numel(synthetic.times) < 2
    error('cuqdyn_generate_synthetic_data:InvalidTimes', ...
        'problem.synthetic_data.times must contain at least two numeric values.');
end
if ~isnumeric(synthetic.initial_values) || numel(synthetic.initial_values) ~= nStates
    error('cuqdyn_generate_synthetic_data:InvalidInitialValues', ...
        'problem.synthetic_data.initial_values must have one value per state.');
end
if ~isnumeric(synthetic.true_parameters) || numel(synthetic.true_parameters) ~= nParams
    error('cuqdyn_generate_synthetic_data:InvalidTrueParameters', ...
        'problem.synthetic_data.true_parameters must have one value per parameter.');
end
if any(synthetic.observed_state_indices < 1) || any(synthetic.observed_state_indices > nStates)
    error('cuqdyn_generate_synthetic_data:InvalidObservedIdx', ...
        'problem.synthetic_data.observed_state_indices contains invalid indices.');
end

if ~isfield(synthetic, 'noise_model') || isempty(synthetic.noise_model)
    synthetic.noise_model = "additive_gaussian_mean_percent";
end
synthetic.noise_model = string(validatestring(char(synthetic.noise_model), ...
    {'none', 'additive_gaussian_mean_percent'}));

if ~isfield(synthetic, 'noise_percent') || isempty(synthetic.noise_percent)
    synthetic.noise_percent = 0;
end
if ~isfield(synthetic, 'min_observed_value') || isempty(synthetic.min_observed_value)
    synthetic.min_observed_value = 0;
end
if ~isfield(synthetic, 'rng_seed')
    synthetic.rng_seed = [];
end
if ~isfield(synthetic, 'make_plots') || isempty(synthetic.make_plots)
    synthetic.make_plots = true;
end
if ~isfield(synthetic, 'ode') || isempty(synthetic.ode)
    synthetic.ode = struct();
end
end

function odeOpts = getOdeOptions(synthetic)
relTol = getFieldWithDefault(synthetic.ode, 'RelTol', 1e-7);
absTol = getFieldWithDefault(synthetic.ode, 'AbsTol', 1e-9);
odeOpts = odeset('RelTol', relTol, 'AbsTol', absTol);
end

function value = getFieldWithDefault(s, fieldName, defaultValue)
if isfield(s, fieldName) && ~isempty(s.(fieldName))
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function [Y_data, sigma] = applyNoise(Y_true, observedIdx, synthetic)
Y_data = Y_true;
sigma = zeros(1, numel(observedIdx));

switch char(synthetic.noise_model)
    case 'none'
        return

    case 'additive_gaussian_mean_percent'
        sigma = cuqdyn_synthetic_sigma_from_trajectory( ...
            Y_true, observedIdx, synthetic.noise_percent);
        for k = 1:numel(observedIdx)
            j = observedIdx(k);
            Y_data(2:end, j) = Y_true(2:end, j) + ...
                sigma(k) * randn(size(Y_true, 1) - 1, 1);
            Y_data(2:end, j) = max(Y_data(2:end, j), ...
                synthetic.min_observed_value);
        end
end
end

function assertNoNegativeFiniteData(Y_data, outputFile)
finiteValues = Y_data(isfinite(Y_data));
if any(finiteValues < 0)
    error('cuqdyn_generate_synthetic_data:NegativeValues', ...
        'Generated negative finite values for %s.', outputFile);
end
end

function plotSyntheticData(T, Y_true, Y_data, isObserved, label)
figure('Color', 'w', 'Name', [label ' synthetic data']);
tiledlayout(numel(isObserved), 1, 'TileSpacing', 'compact');
for j = 1:numel(isObserved)
    nexttile; hold on; grid on;
    plot(T, Y_true(:, j), 'k-', 'LineWidth', 1.5);
    plot(T, Y_data(:, j), 'ro', 'MarkerFaceColor', 'r');
    title(sprintf('%s state y%d', label, j));
    xlabel('Time');
    ylabel(sprintf('y%d', j));
    if isObserved(j)
        legend('Noise-free', 'Synthetic data', 'Location', 'best');
    else
        legend('Noise-free', 'Initial condition only', 'Location', 'best');
    end
end
end

function tf = isAbsolutePath(pathValue)
pathValue = char(pathValue);
if ispc
    tf = ~isempty(regexp(pathValue, '^[A-Za-z]:[\\/]', 'once')) || ...
        startsWith(pathValue, '\\');
else
    tf = startsWith(pathValue, '/');
end
end
