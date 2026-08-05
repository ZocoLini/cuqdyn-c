function summary = run_all_examples(varargin)
%RUN_ALL_EXAMPLES Run all non-SBC example scripts and summarize failures.
%
% This is an integration/smoke-test driver for the example suite. It runs
% the standard example scripts for each method, catches errors per example,
% and performs basic sanity checks on the generated CUQDyn result structs.
%
% Usage:
%   summary = run_all_examples();
%   summary = run_all_examples('StopOnFailure', true);
%
% Notes:
%   - SBC scripts are intentionally excluded.
%   - Each script is run from its own example folder.
%   - Scripts are executed in the base workspace from inside this function
%     so legacy "clear all" statements in examples do not erase this runner.

opts = parseInputs(varargin{:});

repoRoot = fileparts(mfilename('fullpath'));
addpath(genpath(repoRoot));

timestamp = char(string(datetime('now'), 'yyyy-MM-dd_HH-mm-ss'));
masterDir = fullfile(repoRoot, 'EXAMPLES', ['Master_Run_Results_' timestamp]);
if ~exist(masterDir, 'dir')
    mkdir(masterDir);
end
machineInfo = collectMachineInfo();
writeMachineInfo(masterDir, machineInfo);

examples = exampleManifest(repoRoot);
nExamples = numel(examples);
records = repmat(emptyRecord(), nExamples, 1);

fprintf('\n=== CUQDyn1_Plus example-suite run ===\n');
fprintf('Started: %s\n', timestamp);
fprintf('Output:  %s\n', masterDir);
printMachineInfo(machineInfo);
fprintf('SBC scripts are excluded.\n\n');

for k = 1:nExamples
    ex = examples(k);
    fprintf('%s\n', repmat('=', 1, 72));
    fprintf('Example %d / %d: %s [%s]\n', ...
        k, nExamples, char(ex.name), char(ex.method));
    fprintf('Script: %s\n', char(ex.script));

    tStart = tic;
    rec = emptyRecord();
    rec.Name = ex.name;
    rec.Method = ex.method;
    rec.Script = ex.script;

    try
        [outputText, resultDir, runtimeWarnings] = runExampleScript(ex, repoRoot);
        rec.ElapsedSeconds = toc(tStart);
        rec.ResultDir = resultDir;
        rec.LogFile = writeExampleLog(masterDir, k, ex, outputText);

        checks = checkExampleOutput(ex, resultDir);
        checks.warnings = [runtimeWarnings, checks.warnings];
        rec.Status = checks.status;
        rec.NErrors = numel(checks.errors);
        rec.NWarnings = numel(checks.warnings);
        rec.NExpectedWarnings = countWarningsByClass(checks.warnings, "expected");
        rec.NUnexpectedWarnings = countWarningsByClass(checks.warnings, "unexpected");
        rec.Errors = joinMessages(checks.errors);
        rec.Warnings = joinWarningMessages(checks.warnings);
        rec.WarningIDs = joinWarningField(checks.warnings, "id");
        rec.WarningSources = joinWarningField(checks.warnings, "source");
        rec.WarningClasses = joinWarningField(checks.warnings, "classification");
        rec.WarningDetails = joinWarningDetails(checks.warnings);

        if rec.NErrors > 0
            fprintf('Completed with unexpected result(s) in %.1f s.\n', rec.ElapsedSeconds);
            fprintf('%s\n', rec.Errors);
            if opts.StopOnFailure
                records(k) = rec;
                records = records(1:k);
                break;
            end
        else
            fprintf('PASS in %.1f s', rec.ElapsedSeconds);
            if rec.NWarnings > 0
                fprintf(' with %d warning(s)', rec.NWarnings);
            end
            fprintf('.\n');
        end

    catch ME
        rec.ElapsedSeconds = toc(tStart);
        rec.Status = "ERROR";
        rec.NErrors = 1;
        rec.Errors = string(getReport(ME, 'extended', 'hyperlinks', 'off'));
        rec.LogFile = "";
        fprintf('FAILED in %.1f s.\n%s\n', rec.ElapsedSeconds, ME.message);

        if opts.StopOnFailure
            records(k) = rec;
            records = records(1:k);
            break;
        end
    end

    records(k) = rec;
end

summary = struct2table(records);
summaryPathXlsx = fullfile(masterDir, 'master_example_run_summary.xlsx');
summaryPathCsv = fullfile(masterDir, 'master_example_run_summary.csv');
summaryPathMat = fullfile(masterDir, 'master_example_run_summary.mat');
writetable(summary, summaryPathXlsx);
writetable(summary, summaryPathCsv);
save(summaryPathMat, 'summary', 'examples', 'opts', 'machineInfo');

fprintf('\n%s\n', repmat('=', 1, 72));
fprintf('Example-suite summary\n');
disp(summary(:, {'Name','Method','Status','ElapsedSeconds','NErrors', ...
    'NWarnings','NUnexpectedWarnings'}));
fprintf('Summary saved to:\n  %s\n  %s\n', summaryPathXlsx, summaryPathCsv);

if any(summary.Status == "ERROR" | summary.Status == "UNEXPECTED")
    error('run_all_examples:FailuresDetected', ...
        'One or more examples failed or produced unexpected results. See %s', summaryPathXlsx);
end
end

function opts = parseInputs(varargin)
opts = struct();
opts.StopOnFailure = false;

if mod(numel(varargin), 2) ~= 0
    error('run_all_examples:InvalidInputs', ...
        'Options must be supplied as name-value pairs.');
end

for i = 1:2:numel(varargin)
    name = validatestring(varargin{i}, {'StopOnFailure'});
    opts.(name) = varargin{i+1};
end
end

function info = collectMachineInfo()
info = struct();
info.Timestamp = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
info.HostName = firstNonempty(getenv('COMPUTERNAME'), getenv('HOSTNAME'));
info.UserName = firstNonempty(getenv('USERNAME'), getenv('USER'));
info.OS = detectOperatingSystem();
info.Processor = detectProcessor();
[computerType, ~, endian] = computer;
info.MatlabComputer = string(computerType);
info.Endianness = string(endian);
info.MatlabVersion = string(version);
info.MatlabRelease = string(version('-release'));
info.MatlabRoot = string(matlabroot);
try
    info.NumCores = feature('numcores');
catch
    info.NumCores = NaN;
end
end

function printMachineInfo(info)
fprintf('Machine:\n');
fprintf('  Host:      %s\n', char(info.HostName));
fprintf('  OS:        %s\n', char(info.OS));
fprintf('  Processor: %s\n', char(info.Processor));
fprintf('  MATLAB:    %s (%s)\n', char(info.MatlabVersion), char(info.MatlabRelease));
fprintf('  Computer:  %s, %g core(s)\n', char(info.MatlabComputer), info.NumCores);
end

function writeMachineInfo(masterDir, info)
infoTable = struct2table(info);
try
    writetable(infoTable, fullfile(masterDir, 'machine_info.xlsx'));
catch ME
    warning('run_all_examples:MachineInfoWriteFailed', ...
        'Could not write machine_info.xlsx: %s', ME.message);
end
try
    writetable(infoTable, fullfile(masterDir, 'machine_info.csv'));
catch ME
    warning('run_all_examples:MachineInfoWriteFailed', ...
        'Could not write machine_info.csv: %s', ME.message);
end

fid = fopen(fullfile(masterDir, 'machine_info.txt'), 'w');
if fid < 0
    warning('run_all_examples:MachineInfoWriteFailed', ...
        'Could not write machine_info.txt in %s', masterDir);
    return;
end
fields = fieldnames(info);
for i = 1:numel(fields)
    value = info.(fields{i});
    if isnumeric(value)
        value = string(value);
    end
    fprintf(fid, '%s: %s\n', fields{i}, char(string(value)));
end
fclose(fid);
end

function value = detectOperatingSystem()
if ispc
    [status, output] = system('ver');
elseif ismac
    [status, output] = system('sw_vers');
else
    [status, output] = system('uname -a');
end
if status == 0 && strlength(strtrim(string(output))) > 0
    value = strtrim(regexprep(string(output), '\s+', ' '));
else
    value = string(computer);
end
end

function value = detectProcessor()
value = firstNonempty(getenv('PROCESSOR_IDENTIFIER'), getenv('PROCESSOR_ARCHITECTURE'));
if strlength(value) == 0
    if ispc
        [status, output] = system('wmic cpu get name');
        if status == 0
            lines = strip(splitlines(string(output)));
            lines = lines(strlength(lines) > 0 & ~strcmpi(lines, "Name"));
            if ~isempty(lines)
                value = lines(1);
            end
        end
    else
        [status, output] = system('uname -p');
        if status == 0
            value = strtrim(string(output));
        end
    end
end
if strlength(value) == 0
    value = "unknown";
end
end

function value = firstNonempty(varargin)
value = "";
for i = 1:nargin
    candidate = strtrim(string(varargin{i}));
    if strlength(candidate) > 0
        value = candidate;
        return;
    end
end
end

function examples = exampleManifest(repoRoot)
examples = struct('name', {}, 'method', {}, 'script', {}, ...
    'expectedMat', {}, 'referenceSummary', {}, 'referenceRelTol', {});

examples(end+1) = exampleDef('LV', 'CUQDyn1_Plus', ...
    repoRoot, 'EXAMPLES', 'LV', 'run_LV2_CUQDyn1_Plus_partobs_example.m', ...
    'CUQDyn1_Plus_results.mat', '', NaN);
examples(end+1) = exampleDef('LV', 'CUQDyn1_Plus_HybridCov', ...
    repoRoot, 'EXAMPLES', 'LV', 'run_LV2_CUQDyn1_Plus_HybridCov_partobs_example.m', ...
    'CUQDyn1_Plus_HybridCov_results.mat', '', NaN);

examples(end+1) = exampleDef('SIR', 'CUQDyn1_Plus', ...
    repoRoot, 'EXAMPLES', 'SIR', 'run_SIR_CUQDyn1Plus.m', ...
    'CUQDyn1_Plus_results.mat', '', NaN);
examples(end+1) = exampleDef('SIR', 'CUQDyn1_Plus_HybridCov', ...
    repoRoot, 'EXAMPLES', 'SIR', 'run_SIR_CUQDyn1Plus_HybridCov.m', ...
    'CUQDyn1_Plus_HybridCov_results.mat', '', NaN);

examples(end+1) = exampleDef('AP', 'CUQDyn1_Plus', ...
    repoRoot, 'EXAMPLES', 'AP', 'run_AP_CUQDyn1Plus_partobs_example.m', ...
    'CUQDyn1_Plus_results.mat', '', NaN);
examples(end+1) = exampleDef('AP', 'CUQDyn1_Plus_HybridCov', ...
    repoRoot, 'EXAMPLES', 'AP', 'run_AP_CUQDyn1Plus_HybridCov_partobs_example.m', ...
    'CUQDyn1_Plus_HybridCov_results.mat', '', NaN);

examples(end+1) = exampleDef('NFKB', 'CUQDyn1_Plus', ...
    repoRoot, 'EXAMPLES', 'NFKB', 'run_NFKB_example_CUQDyn1plus.m', ...
    'CUQDyn1_Plus_results.mat', '', NaN);
examples(end+1) = exampleDef('NFKB', 'CUQDyn1_Plus_HybridCov', ...
    repoRoot, 'EXAMPLES', 'NFKB', 'run_NFKB_example_CUQDyn1plus_HybCov.m', ...
    'CUQDyn1_Plus_HybridCov_results.mat', '', NaN);

examples(end+1) = exampleDef('LinearCascade', 'CUQDyn1_Plus', ...
    repoRoot, 'EXAMPLES', 'LinearCascade', 'diagnose_LinearCascade_known_truth.m', ...
    'CUQDyn1_Plus_results.mat', 'linear_cascade_numerics_summary.xlsx', 1e-3);
examples(end+1) = exampleDef('LinearCascade3', 'CUQDyn1_Plus', ...
    repoRoot, 'EXAMPLES', 'LinearCascade', 'diagnose_LinearCascade3_known_truth.m', ...
    'CUQDyn1_Plus_results.mat', 'linear_cascade3_numerics_summary.xlsx', 1e-3);
end

function ex = exampleDef(name, method, repoRoot, varargin)
if numel(varargin) < 4
    error('run_all_examples:InvalidManifestEntry', ...
        'Each manifest entry needs folder parts, script, expected MAT, reference summary, and tolerance.');
end

referenceRelTol = varargin{end};
referenceSummary = varargin{end-1};
expectedMat = varargin{end-2};
scriptName = varargin{end-3};
scriptParts = varargin(1:end-4);

ex = struct();
ex.name = string(name);
ex.method = string(method);
ex.script = fullfile(repoRoot, scriptParts{:}, scriptName);
ex.expectedMat = string(expectedMat);
ex.referenceSummary = string(referenceSummary);
ex.referenceRelTol = referenceRelTol;
end

function [outputText, resultDir, runtimeWarnings] = runExampleScript(ex, repoRoot)
if ~exist(ex.script, 'file')
    error('run_all_examples:MissingScript', 'Missing example script: %s', ex.script);
end

scriptPath = char(ex.script);
exampleDir = fileparts(scriptPath);

evalin('base', 'clear variables;');
evalin('base', sprintf('addpath(genpath(''%s''));', escapeForMatlab(repoRoot)));
basePwd = evalin('base', 'pwd');
evalin('base', sprintf('cd(''%s'');', escapeForMatlab(exampleDir)));
try
    baseCmd = sprintf('run(''%s'');', escapeForMatlab(scriptPath));
    lastwarn('', '');
    outputText = evalc(sprintf('evalin(''base'', ''%s'');', escapeForMatlab(baseCmd)));
    [lastWarnMsg, lastWarnId] = lastwarn();
    runtimeWarnings = collectRuntimeWarnings(outputText, lastWarnMsg, ...
        lastWarnId, ex.script);
catch ME
    evalin('base', sprintf('cd(''%s'');', escapeForMatlab(basePwd)));
    rethrow(ME);
end
evalin('base', sprintf('cd(''%s'');', escapeForMatlab(basePwd)));

if evalin('base', 'exist(''resultDir'', ''var'')')
    resultDir = evalin('base', 'resultDir');
    resultDir = char(resultDir);
    if ~isAbsolutePath(resultDir)
        resultDir = fullfile(exampleDir, resultDir);
    end
else
    resultDir = '';
end
end

function checks = checkExampleOutput(ex, resultDir)
checks = struct('status', "PASS", 'errors', {{}}, ...
    'warnings', emptyWarningRecord());

if strlength(string(resultDir)) == 0
    checks.errors{end+1} = 'The script did not define resultDir.';
    checks.status = "UNEXPECTED";
    return;
end

if ~exist(resultDir, 'dir')
    checks.errors{end+1} = sprintf('Result directory was not created: %s', resultDir);
    checks.status = "UNEXPECTED";
    return;
end

resultMat = fullfile(resultDir, char(ex.expectedMat));
if ~exist(resultMat, 'file')
    checks.errors{end+1} = sprintf('Expected result MAT file missing: %s', resultMat);
    checks.status = "UNEXPECTED";
    return;
end

S = load(resultMat);
if ~isfield(S, 'results')
    checks.errors{end+1} = sprintf('MAT file does not contain a results struct: %s', resultMat);
    checks.status = "UNEXPECTED";
    return;
end

results = S.results;
requiredFields = {'parameters_init', 'media_tot', 'UQ_lower', 'UQ_upper'};
for i = 1:numel(requiredFields)
    if ~isfield(results, requiredFields{i})
        checks.errors{end+1} = sprintf('Missing results.%s.', requiredFields{i});
    end
end

if ~isempty(checks.errors)
    checks.status = "UNEXPECTED";
    return;
end

checks = checkNumericArray(checks, results.parameters_init, 'results.parameters_init', true);
checks = checkNumericArray(checks, results.media_tot, 'results.media_tot', true);
checks = checkNumericArray(checks, results.UQ_lower, 'results.UQ_lower', true);
checks = checkNumericArray(checks, results.UQ_upper, 'results.UQ_upper', true);

if isequal(size(results.media_tot), size(results.UQ_lower)) && ...
        isequal(size(results.media_tot), size(results.UQ_upper))
    badWidth = results.UQ_upper < results.UQ_lower;
    if any(badWidth(:))
        checks.errors{end+1} = sprintf('UQ_upper is below UQ_lower at %d entries.', nnz(badWidth));
    end
else
    checks.errors{end+1} = 'media_tot, UQ_lower, and UQ_upper dimensions do not match.';
end

if isfield(results, 'Cov_p')
    checks = checkNumericArray(checks, results.Cov_p, 'results.Cov_p', true);
    if isnumeric(results.Cov_p) && ismatrix(results.Cov_p) && ...
            size(results.Cov_p, 1) == size(results.Cov_p, 2)
        symErr = norm(results.Cov_p - results.Cov_p', 'fro');
        if symErr > 1e-6 * max(norm(results.Cov_p, 'fro'), eps)
            checks = addWarning(checks, 'run_all_examples:CovPSymmetry', ...
                sprintf('Cov_p is not very symmetric; relative symmetry error %.3g.', ...
                symErr / max(norm(results.Cov_p, 'fro'), eps)), ex.script);
        end
        eigVals = eig((results.Cov_p + results.Cov_p') / 2);
        if min(eigVals) < -1e-8 * max(max(abs(eigVals)), 1)
            checks.errors{end+1} = sprintf('Cov_p has a negative eigenvalue %.3g.', min(eigVals));
        elseif min(eigVals) < 0
            checks = addWarning(checks, 'run_all_examples:TinyNegativeCovEigenvalue', ...
                sprintf('Cov_p has a tiny negative eigenvalue %.3g.', min(eigVals)), ...
                ex.script);
        end
    end
end

if isfield(results, 'parameters_init') && isnumeric(results.parameters_init)
    theta = results.parameters_init(:);
    if evalin('base', 'exist(''lb_params'', ''var'') && exist(''ub_params'', ''var'')')
        lb = evalin('base', 'lb_params(:)');
        ub = evalin('base', 'ub_params(:)');
        if numel(theta) == numel(lb) && numel(theta) == numel(ub)
            tol = 1e-8 * max(1, max(abs([lb; ub])));
            if any(theta < lb - tol) || any(theta > ub + tol)
                checks.errors{end+1} = 'Estimated parameters are outside declared bounds.';
            end
            boundRange = max(abs(ub - lb), eps);
            nearLower = abs(theta - lb) <= 1e-4 * boundRange;
            nearUpper = abs(theta - ub) <= 1e-4 * boundRange;
            if any(nearLower | nearUpper)
                checks = addWarning(checks, 'run_all_examples:NearParameterBound', ...
                    sprintf('%d parameter(s) are very near a bound.', nnz(nearLower | nearUpper)), ...
                    ex.script);
            end
        end
    end
end

if strlength(ex.referenceSummary) > 0
    checks = checkReferenceSummary(checks, resultDir, char(ex.referenceSummary), ...
        ex.referenceRelTol, ex.script);
end

if isempty(checks.errors)
    if isempty(checks.warnings)
        checks.status = "PASS";
    else
        checks.status = "PASS_WITH_WARNINGS";
    end
else
    checks.status = "UNEXPECTED";
end
end

function checks = checkNumericArray(checks, value, label, requireFinite)
if ~isnumeric(value) || isempty(value)
    checks.errors{end+1} = sprintf('%s is missing, empty, or non-numeric.', label);
    return;
end

if requireFinite && any(~isfinite(value(:)))
    checks.errors{end+1} = sprintf('%s contains non-finite values.', label);
end
end

function checks = checkReferenceSummary(checks, resultDir, summaryFile, relTol, scriptPath)
summaryPath = fullfile(resultDir, summaryFile);
if ~exist(summaryPath, 'file')
    checks = addWarning(checks, 'run_all_examples:ReferenceSummaryMissing', ...
        sprintf('Reference summary missing: %s', summaryPath), scriptPath);
    return;
end

try
    T = readtable(summaryPath, 'Sheet', 'Summary');
    relVars = T.Properties.VariableNames(contains(T.Properties.VariableNames, 'RelError'));
    for i = 1:numel(relVars)
        vals = T.(relVars{i});
        if isnumeric(vals) && any(vals > relTol)
            checks.errors{end+1} = sprintf('%s exceeds tolerance %.3g in %s.', relVars{i}, relTol, summaryFile);
        end
    end

    absVars = T.Properties.VariableNames(contains(T.Properties.VariableNames, 'MaxTrajectory'));
    for i = 1:numel(absVars)
        vals = T.(absVars{i});
        if isnumeric(vals) && any(vals > 1e-4)
            checks.errors{end+1} = sprintf('%s exceeds trajectory tolerance in %s.', absVars{i}, summaryFile);
        end
    end
catch ME
    checks = addWarning(checks, 'run_all_examples:ReferenceSummaryReadFailed', ...
        sprintf('Could not read reference summary %s: %s', summaryPath, ME.message), ...
        scriptPath);
end
end

function logPath = writeExampleLog(masterDir, idx, ex, outputText)
safeName = regexprep(char(ex.name + "_" + ex.method), '[^A-Za-z0-9_]+', '_');
logPath = fullfile(masterDir, sprintf('%02d_%s.log', idx, safeName));
fid = fopen(logPath, 'w');
if fid < 0
    warning('run_all_examples:LogOpenFailed', 'Could not write log: %s', logPath);
    logPath = "";
    return;
end
cleanupObj = onCleanup(@() fclose(fid));
fprintf(fid, 'Example: %s\nMethod: %s\nScript: %s\n\n', ...
    char(ex.name), char(ex.method), char(ex.script));
fprintf(fid, '%s', outputText);
clear cleanupObj;
end

function rec = emptyRecord()
rec = struct();
rec.Name = "";
rec.Method = "";
rec.Status = "NOT_RUN";
rec.ElapsedSeconds = NaN;
rec.NErrors = NaN;
rec.NWarnings = NaN;
rec.NExpectedWarnings = NaN;
rec.NUnexpectedWarnings = NaN;
rec.Script = "";
rec.ResultDir = "";
rec.LogFile = "";
rec.Errors = "";
rec.Warnings = "";
rec.WarningIDs = "";
rec.WarningSources = "";
rec.WarningClasses = "";
rec.WarningDetails = "";
end

function out = joinMessages(messages)
if isempty(messages)
    out = "";
else
    out = strjoin(string(messages), newline);
end
end

function warnings = emptyWarningRecord()
warnings = struct('id', {}, 'message', {}, 'source', {}, 'classification', {});
end

function checks = addWarning(checks, id, message, source)
checks.warnings(end+1) = makeWarning(id, message, source);
end

function warningRec = makeWarning(id, message, source)
warningRec = struct( ...
    'id', string(id), ...
    'message', string(message), ...
    'source', string(source), ...
    'classification', classifyWarning(id));
end

function classification = classifyWarning(id)
% Only warnings explicitly listed here are expected. New warning IDs default
% to unexpected so the master runner calls attention to new behavior.
expectedIds = "run_all_examples:TinyNegativeCovEigenvalue";
if any(string(id) == expectedIds)
    classification = "expected";
else
    classification = "unexpected";
end
end

function warnings = collectRuntimeWarnings(outputText, lastWarnMsg, lastWarnId, source)
warnings = emptyWarningRecord();
outputWarnings = parseOutputWarnings(outputText, source);
warnings = [warnings, outputWarnings];

if strlength(string(lastWarnMsg)) > 0
    lastWarning = makeWarning(normalizeWarningId(lastWarnId), lastWarnMsg, source);
    if ~containsWarning(warnings, lastWarning)
        warnings(end+1) = lastWarning;
    end
end
end

function warnings = parseOutputWarnings(outputText, source)
warnings = emptyWarningRecord();
lines = splitlines(string(outputText));
for i = 1:numel(lines)
    line = strtrim(lines(i));
    if startsWith(line, "Warning:")
        msg = strtrim(extractAfter(line, "Warning:"));
        if strlength(msg) == 0
            msg = line;
        end
        warnings(end+1) = makeWarning('run_all_examples:RuntimeWarning', msg, source); %#ok<AGROW>
    end
end
end

function id = normalizeWarningId(id)
id = string(id);
if strlength(id) == 0
    id = "run_all_examples:RuntimeWarning";
end
end

function tf = containsWarning(warnings, candidate)
tf = false;
for i = 1:numel(warnings)
    if warnings(i).id == candidate.id && warnings(i).message == candidate.message
        tf = true;
        return;
    end
end
end

function n = countWarningsByClass(warnings, classification)
n = nnz(string({warnings.classification}) == string(classification));
end

function out = joinWarningMessages(warnings)
if isempty(warnings)
    out = "";
else
    out = strjoin(string({warnings.message}), newline);
end
end

function out = joinWarningField(warnings, fieldName)
if isempty(warnings)
    out = "";
else
    fieldName = char(fieldName);
    out = strjoin(string({warnings.(fieldName)}), newline);
end
end

function out = joinWarningDetails(warnings)
if isempty(warnings)
    out = "";
    return;
end

details = strings(1, numel(warnings));
for i = 1:numel(warnings)
    details(i) = sprintf('[%s][%s][%s] %s', warnings(i).classification, ...
        warnings(i).id, warnings(i).source, warnings(i).message);
end
out = strjoin(details, newline);
end

function tf = isAbsolutePath(pathText)
pathText = char(pathText);
tf = startsWith(pathText, filesep) || ...
    (~isempty(regexp(pathText, '^[A-Za-z]:[\\/]', 'once')));
end

function escaped = escapeForMatlab(pathText)
escaped = strrep(char(pathText), '''', '''''');
end
