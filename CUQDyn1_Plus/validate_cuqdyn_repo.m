function summary = validate_cuqdyn_repo()
%VALIDATE_CUQDYN_REPO Run lightweight local validation checks.
%
% This script is intended as a fast pre-push / CI-style health check. It does
% not run optimizer examples, run_all_examples.m, or SBC scripts.
%
% Usage:
%   summary = validate_cuqdyn_repo();

repoRoot = fileparts(mfilename('fullpath'));
addpath(genpath(repoRoot));

fprintf('\n=== CUQDyn1_Plus lightweight validation ===\n');
fprintf('Repo root: %s\n\n', repoRoot);

records = emptyRecord();
records(1) = runCheck("Path setup", @() checkPathSetup(repoRoot));
records(end+1) = runCheck("Code Analyzer smoke", @() checkCodeAnalyzer(repoRoot));
records(end+1) = runCheck("Problem definitions", @() checkProblemDefinitions(repoRoot));
records(end+1) = runCheck("CSV observability metadata", @() checkCsvObservability(repoRoot));
records(end+1) = runCheck("Generated module equivalence", @() checkGeneratedModules(repoRoot));
records(end+1) = runCheck("Tiny generated LV smoke", @() checkTinyLvSmoke(repoRoot));

summary = struct2table(records);
disp(summary(:, {'Check','Status','Detail'}));

if any(summary.Status == "FAIL")
    error('validate_cuqdyn_repo:Failed', ...
        'One or more lightweight validation checks failed.');
end

fprintf('Lightweight validation completed without failures.\n');
end

function rec = emptyRecord()
rec = struct('Check', "", 'Status', "", 'Detail', "", 'ElapsedSeconds', NaN);
end

function rec = runCheck(name, fcn)
tStart = tic;
rec = emptyRecord();
rec.Check = string(name);
try
    detail = fcn();
    if isstruct(detail)
        rec.Status = detail.status;
        rec.Detail = detail.message;
    else
        rec.Status = "PASS";
        rec.Detail = string(detail);
    end
catch ME
    rec.Status = "FAIL";
    rec.Detail = string(ME.message);
end
rec.ElapsedSeconds = toc(tStart);
fprintf('%-34s %s\n', char(rec.Check), char(rec.Status));
if rec.Status ~= "PASS"
    fprintf('  %s\n', char(rec.Detail));
end
end

function detail = warnDetail(message)
detail = struct('status', "WARN", 'message', string(message));
end

function msg = checkPathSetup(repoRoot)
requiredFiles = {
    fullfile(repoRoot, 'src', 'CUQDyn1_Plus.m')
    fullfile(repoRoot, 'src', 'CUQDyn1_Plus_HybridCov.m')
    fullfile(repoRoot, 'src', 'cuqdyn_validate_problem.m')
    fullfile(repoRoot, 'EXAMPLES', 'check_generated_problem_definitions.m')
};

for i = 1:numel(requiredFiles)
    if ~isfile(requiredFiles{i})
        error('Missing required file: %s', requiredFiles{i});
    end
end

requiredFunctions = ["CUQDyn1_Plus", "CUQDyn1_Plus_HybridCov", ...
    "cuqdyn_validate_problem", "check_generated_problem_definitions"];
for i = 1:numel(requiredFunctions)
    if exist(char(requiredFunctions(i)), 'file') ~= 2
        error('Function not found on MATLAB path: %s', requiredFunctions(i));
    end
end

msg = sprintf('Found %d required functions/files.', numel(requiredFunctions));
end

function detail = checkCodeAnalyzer(repoRoot)
files = {
    fullfile(repoRoot, 'src', 'CUQDyn1_Plus.m')
    fullfile(repoRoot, 'src', 'CUQDyn1_Plus_HybridCov.m')
    fullfile(repoRoot, 'src', 'cuqdyn_generate_problem_files.m')
    fullfile(repoRoot, 'src', 'cuqdyn_validate_problem.m')
    fullfile(repoRoot, 'run_all_examples.m')
    fullfile(repoRoot, 'validate_cuqdyn_repo.m')
    };

totalMessages = 0;
for i = 1:numel(files)
    if ~isfile(files{i})
        error('Missing file for Code Analyzer check: %s', files{i});
    end
    messages = checkcode(files{i}, '-id');
    totalMessages = totalMessages + numel(messages);
end

if totalMessages > 0
    detail = warnDetail(sprintf('Code Analyzer returned %d message(s). Review with checkcode for details.', totalMessages));
else
    detail = 'No Code Analyzer messages in selected core files.';
end
end

function msg = checkProblemDefinitions(repoRoot)
cases = problemDefinitionCases(repoRoot);

for i = 1:numel(cases)
    problem = cases(i).defineFcn();
    problem = cuqdyn_validate_problem(problem);
    if ~isfield(problem, 'observed_state_indices') || isempty(problem.observed_state_indices)
        error('%s is missing observed_state_indices.', problem.name);
    end
    validateObservedIndices(problem);
end

msg = sprintf('Validated %d maintained problem definitions.', numel(cases));
end

function msg = checkCsvObservability(repoRoot)
cases = problemDefinitionCases(repoRoot);

for i = 1:numel(cases)
    problem = cases(i).defineFcn();
    csvPath = resolveProblemCsv(cases(i).exampleDir, problem);
    observedFromCsv = observedIndicesFromCsv(csvPath);
    observedFromProblem = problem.observed_state_indices(:)';
    if ~isequal(observedFromProblem, observedFromCsv)
        error(['%s observed_state_indices %s do not match finite ', ...
            'post-initial CSV columns %s in %s.'], ...
            problem.name, mat2str(observedFromProblem), ...
            mat2str(observedFromCsv), csvPath);
    end
end

msg = sprintf('CSV observability matches %d problem definitions.', numel(cases));
end

function msg = checkGeneratedModules(~)
reports = check_generated_problem_definitions();
if isempty(reports) || ~all([reports.passed])
    error('Generated problem module equivalence failed.');
end

maxDiff = max([
    [reports.maxDynamicsDifference], ...
    [reports.maxComplexDynamicsDifference], ...
    [reports.costDifference], ...
    [reports.gradientDifference], ...
    [reports.maxResidualDifference]]);
if maxDiff > 1e-10
    error('Generated module equivalence max difference %.3g exceeds tolerance.', maxDiff);
end

msg = sprintf('Generated dynamics/cost checks passed for %d problems.', numel(reports));
end

function msg = checkTinyLvSmoke(~)
problem = define_problem_LV();
tmpBase = tempname;
mkdir(tmpBase);
cleanupDir = onCleanup(@() removeTempDir(tmpBase));

generatedDir = fullfile(tmpBase, 'generated_problem');
cuqdyn_generate_problem_files(problem, generatedDir, 'Overwrite', true);
addpath(generatedDir, '-begin');
cleanupPath = onCleanup(@() removePathIfPresent(generatedDir));

dynHandle = @prob_mod_dynamics_LV;
out = cuqdyn_generate_synthetic_data(problem, ...
    'BaseDir', tmpBase, 'DynamicsHandle', dynHandle);

[dataDir, dataName, ext] = fileparts(char(out.outputCsv));
[times, allData, initialValues, observedData, observedIdx] = ...
    loadStateData(dataDir, [dataName, ext], numel(problem.states));

opts = cuqdyn_default_options(numel(problem.parameters));
opts.cost = cuqdyn_cost_options_from_problem(problem, out.Y_true, observedIdx);
odeOpts = cuqdyn_odeset_from_options(opts.ode);
costHandle = @prob_mod_cost_LV;
[J, g, R] = costHandle(problem.true_parameters(:)', times, observedData, ...
    observedIdx, dynHandle, initialValues, odeOpts, opts.cost);

if ~isfinite(J) || ~isfinite(g) || isempty(R) || any(~isfinite(R(:)))
    error('Tiny LV generated cost smoke check produced invalid outputs.');
end
if ~isequal(observedIdx(:)', problem.observed_state_indices(:)')
    error('Tiny LV generated data observed indices do not match problem definition.');
end
if min(allData(isfinite(allData))) < 0
    error('Tiny LV generated data contains negative finite values.');
end

clear cleanupPath
clear cleanupDir
msg = sprintf('Generated LV data/cost smoke passed, J=%.4g.', J);
end

function cases = problemDefinitionCases(repoRoot)
cases = struct('name', {}, 'defineFcn', {}, 'exampleDir', {});
cases(end+1) = caseDef("AP", @define_problem_AP, fullfile(repoRoot, 'EXAMPLES', 'AP'));
cases(end+1) = caseDef("LV", @define_problem_LV, fullfile(repoRoot, 'EXAMPLES', 'LV'));
cases(end+1) = caseDef("SIR", @define_problem_SIR, fullfile(repoRoot, 'EXAMPLES', 'SIR'));
cases(end+1) = caseDef("NFKB", @define_problem_NFKB, fullfile(repoRoot, 'EXAMPLES', 'NFKB'));
cases(end+1) = caseDef("LinearCascade", @define_problem_LinearCascade, fullfile(repoRoot, 'EXAMPLES', 'LinearCascade'));
cases(end+1) = caseDef("LinearCascade3", @define_problem_LinearCascade3, fullfile(repoRoot, 'EXAMPLES', 'LinearCascade'));
end

function c = caseDef(name, defineFcn, exampleDir)
c = struct('name', string(name), 'defineFcn', defineFcn, 'exampleDir', exampleDir);
end

function validateObservedIndices(problem)
nStates = numel(problem.states);
idx = problem.observed_state_indices;
if ~isnumeric(idx) || isempty(idx) || any(idx ~= fix(idx)) || ...
        any(idx < 1) || any(idx > nStates) || numel(unique(idx)) ~= numel(idx)
    error('%s has invalid observed_state_indices.', problem.name);
end

if isfield(problem, 'observed_states') && ~isempty(problem.observed_states)
    expectedNames = problem.states(idx);
    declaredNames = string(problem.observed_states(:));
    if ~isequal(declaredNames(:), expectedNames(:))
        error('%s observed_states do not match observed_state_indices.', problem.name);
    end
end
end

function csvPath = resolveProblemCsv(exampleDir, problem)
folder = char(problem.data.folder);
fileName = char(problem.data.file);
candidate = fullfile(exampleDir, folder, fileName);
if isfile(candidate)
    csvPath = candidate;
    return
end

alt = fullfile(exampleDir, lower(folder), fileName);
if isfile(alt)
    csvPath = alt;
    return
end

alt = fullfile(exampleDir, upper(folder), fileName);
if isfile(alt)
    csvPath = alt;
    return
end

error('Could not find configured CSV for %s: %s', problem.name, candidate);
end

function observedIdx = observedIndicesFromCsv(csvPath)
T = readtable(csvPath, 'PreserveVariableNames', true);
Y = table2array(T(:, 2:end));
if size(Y, 1) < 2
    observedIdx = [];
else
    observedIdx = find(any(isfinite(Y(2:end, :)), 1));
end
end

function removeTempDir(folderPath)
if exist(folderPath, 'dir')
    rmdir(folderPath, 's');
end
end

function removePathIfPresent(folderPath)
pathParts = strsplit(path, pathsep);
if any(strcmp(pathParts, folderPath))
    rmpath(folderPath);
end
end
