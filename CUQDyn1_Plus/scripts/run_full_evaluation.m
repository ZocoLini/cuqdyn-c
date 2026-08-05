function summary = run_full_evaluation(varargin)
%RUN_FULL_EVALUATION  Batch runner for the CUQDyn1_Plus manuscript evaluation.
%
%   Reproduces the end-to-end pipeline described in
%   scripts/how_to_generate_figures_tables.md as a single, unattended
%   `matlab -batch` job. Every stage is isolated in a try/catch, timed, and
%   logged, so one failure does not abort the rest. A summary table is printed
%   and saved at the end.
%
% ---------------------------------------------------------------------------
% HOW TO RUN  (Windows PowerShell)
% ---------------------------------------------------------------------------
%   Robust launch (does NOT depend on the current folder or the MATLAB path;
%   this is the recommended, copy-paste form):
%       matlab -batch "addpath(genpath('<repo>')); run_full_evaluation"
%
%   A `matlab -batch` process inherits environment variables from the shell
%   that launches it, so `$env:MEIGO64_PATH` set in the SAME PowerShell session
%   is visible. The trap is a MEIGO64_PATH that was only set in a different
%   shell/session (or never set/persisted): MATLAB will not see it and the
%   runner falls back to <repo>\MEIGO64-master. Set it in the launching session,
%   or pass MeigoPath. Detached full run, recommended for the long job:
%       $env:MEIGO64_PATH = '<meigo>\MEIGO64-master'
%       Start-Process matlab -ArgumentList '-batch', `
%         "addpath(genpath('<repo>')); run_full_evaluation" -WorkingDirectory '<repo>\scripts'
%     or pass MEIGO explicitly (the repo still needs to be on the path):
%       matlab -batch "addpath(genpath('<repo>')); run_full_evaluation('MeigoPath','<meigo>\MEIGO64-master')"
%
%   Selected stages only (names are case-insensitive):
%       matlab -batch "run_full_evaluation('Stages', [""examples"",""tutorial""])"
%
%   Faster SBC variants (dev checks only). *_fast SBC folders do NOT match the
%   standard prefixes the report generators expect, so the 'reports' stage is
%   SKIPPED when UseFastSBC=true unless AllowFastReports is also set:
%       matlab -batch "run_full_evaluation('UseFastSBC', true)"                    % reports skipped
%       matlab -batch "run_full_evaluation('UseFastSBC', true, 'AllowFastReports', true)"
%
% ---------------------------------------------------------------------------
% PREREQUISITES
% ---------------------------------------------------------------------------
%   * MATLAB R2021a or later (developed on R2026a).
%   * MEIGO64 optimiser. Set the MEIGO64_PATH environment variable, or pass
%     'MeigoPath', or place MEIGO64-master next to the repo root. Optimisation
%     stages (examples, tutorial, sbc, pymc plots) require it.
%   * For the PyMC / reports stages (Steps 5-7): `uv` on PATH and the env
%     created once via `uv sync` in <repo>\pymc_matlab. A C++ compiler
%     (MSYS2 UCRT64 g++, i.e. C:\msys64\ucrt64\bin) must be on PATH so PyTensor
%     can compile; this runner prepends 'Ucrt64Bin' to PATH automatically if it
%     exists. BLAS is picked up from ~/.pytensorrc if configured.
%   * Figures: MATLAB should be in LIGHT theme for manuscript-ready output. The
%     theme is a persistent user setting (settings.matlab.appearance.MATLABTheme
%     = "Light"); the runner logs the active theme so you can confirm.
%
% ---------------------------------------------------------------------------
% STAGES (executed in this order; maps to how_to_generate_figures_tables.md)
% ---------------------------------------------------------------------------
%   setup     (always) Step 1  - add repo + MEIGO to path, set PATH for PyMC.
%   validate           Step 1  - validate_cuqdyn_repo() lightweight health check.
%   examples           Step 2  - run_all_examples(): LV/SIR/AP/NF-kB (FIM +
%                                 HybridCov) and LinearCascade(3) diagnostics,
%                                 then generate_uq_diagnostics() for the main
%                                 runs (writes uq_diagnostics.xlsx for the SI).
%   tutorial           Step 3  - EXAMPLES/LV/tutorial_LV_three_prediction_UQ_methods.
%   sbc                Step 4  - SBC calibration for LV, SIR, AP, LinearCascade3.
%   pymc               Step 5  - `uv sync` then run_bayes_{lv,sir,ap,nfkb}
%                                 (each calls uv run python <model>_pymc.py).
%   compare            Step 6  - pymc_matlab/compare_cuqdyn_pymc.
%   reports            Step 7  - the three scripts/generate_*.py LaTeX reports.
%
%   Steps 8 (copy figures into the manuscript) and 9 (date convention) from the
%   guide are manual and are intentionally NOT automated here.
%
% ---------------------------------------------------------------------------
% OPTIONS (name-value)
% ---------------------------------------------------------------------------
%   'Stages'          string array of stage names, or "all" (default).
%   'ContinueOnError' logical, default true - keep going after a stage fails.
%                     Even so, a consumer stage ('compare','reports') is
%                     SKIPPED (not run on stale outputs) when one of its
%                     in-run producer stages did not PASS -- see STAGE
%                     DEPENDENCIES below.
%   'UseFastSBC'      logical, default false - use *_fast SBC variants.
%   'AllowFastReports' logical, default false - permit the 'reports' stage to
%                     run even when UseFastSBC=true. Off by default because
%                     *_fast SBC folder names do not match the prefixes the
%                     report generators expect (reports would use older
%                     standard SBC outputs).
%   'MeigoPath'       char, default '' - overrides MEIGO64_PATH detection.
%   'Ucrt64Bin'       char, default 'C:\msys64\ucrt64\bin' - g++ dir for PyMC.
%   'RunUvSync'       logical, default true - run `uv sync` before PyMC stage.
%
%   run_full_evaluation('list') returns the ordered stage names and exits.
%
% ---------------------------------------------------------------------------
% STAGE DEPENDENCIES (enforced only among stages selected for THIS run)
% ---------------------------------------------------------------------------
%   compare  requires  examples, pymc
%   reports  requires  examples, tutorial, sbc, compare
%   If a required producer stage is part of the run and does not PASS, the
%   dependent stage is marked SKIPPED so it cannot silently consume an older
%   "latest" folder. Running a consumer stage on its own (e.g. only 'reports')
%   deliberately reuses whatever standard outputs already exist.
%
% ---------------------------------------------------------------------------
% OUTPUTS
% ---------------------------------------------------------------------------
%   * Per-example result folders under EXAMPLES/<model>/ (timestamped).
%   * Master run summary under EXAMPLES/Master_Run_Results_<timestamp>/.
%   * LaTeX/CSV/XLSX reports under REPORTS/ (date-stamped).
%   * This runner's diary log + summary under scripts/eval_logs/<timestamp>/.
%   * Returned/echoed `summary` table: stage, status, elapsed seconds, message.
%
%   Copyright 2026. Runner authored for the CUQDyn1_Plus manuscript workflow.

% --- Special "list" invocation -------------------------------------------
if nargin == 1 && (isstring(varargin{1}) || ischar(varargin{1})) ...
        && strcmpi(varargin{1}, 'list')
    summary = allStageNames();
    return;
end

opts = parseOptions(varargin{:});

% ========================= SETUP (Step 1) ================================
thisFile = mfilename('fullpath');
scriptsDir = fileparts(thisFile);
repoRoot = fileparts(scriptsDir);

runStamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
logDir = fullfile(scriptsDir, 'eval_logs', runStamp);
if ~exist(logDir, 'dir'); mkdir(logDir); end
diaryFile = fullfile(logDir, 'run_full_evaluation.log');
diary(diaryFile); diary on;
cleanupDiary = onCleanup(@() diary('off'));

fprintf('\n==========================================================\n');
fprintf(' CUQDyn1_Plus full evaluation\n');
fprintf(' Started : %s\n', runStamp);
fprintf(' Repo    : %s\n', repoRoot);
fprintf(' Log     : %s\n', diaryFile);
fprintf('==========================================================\n');

% Path setup
addpath(genpath(repoRoot));

% MEIGO detection: option > MEIGO64_PATH env > <repoRoot>\MEIGO64-master
meigoPath = opts.MeigoPath;
if isempty(meigoPath); meigoPath = getenv('MEIGO64_PATH'); end
if isempty(meigoPath); meigoPath = fullfile(repoRoot, 'MEIGO64-master'); end
if isfolder(meigoPath)
    addpath(genpath(meigoPath));
    setenv('MEIGO64_PATH', meigoPath);
    fprintf(' MEIGO   : %s\n', meigoPath);
else
    fprintf(2, ' MEIGO   : NOT FOUND at %s (optimisation stages will fail)\n', meigoPath);
end
fprintf(' which MEIGO -> %s\n', which('MEIGO'));

% Prepend the MSYS2 UCRT64 bin (g++) to PATH for the PyMC/reports stages.
if isfolder(opts.Ucrt64Bin)
    p = getenv('PATH');
    if ~contains(p, opts.Ucrt64Bin)
        setenv('PATH', [opts.Ucrt64Bin pathsep p]);
    end
    fprintf(' PyMC g++: %s (on PATH)\n', opts.Ucrt64Bin);
else
    fprintf(' PyMC g++: %s not found; PyTensor may fall back to slow Python.\n', opts.Ucrt64Bin);
end

% Report the figure theme so manuscript figures can be confirmed light.
try
    s = settings;
    fprintf(' Theme   : %s\n', s.matlab.appearance.MATLABTheme.ActiveValue);
    ftest = figure('Visible', 'off');
    fprintf(' Figure  : BaseColorStyle = %s\n', ftest.Theme.BaseColorStyle);
    close(ftest);
catch
    fprintf(' Theme   : (could not query)\n');
end
fprintf('----------------------------------------------------------\n');

% ========================= STAGE DISPATCH ================================
stages = resolveStages(opts.Stages);
records = struct('Stage', {}, 'Status', {}, 'ElapsedSeconds', {}, 'Message', {});

% Consumer stages must not run on STALE outputs when an in-run producer
% stage failed (with ContinueOnError=true the pipeline keeps going, so a
% failed 'examples'/'pymc' must not let 'compare'/'reports' silently pick up
% an older "latest" folder). Only prerequisites that are themselves part of
% THIS run are enforced -- running 'reports' on its own deliberately reuses
% whatever standard folders already exist.
deps = containers.Map('KeyType', 'char', 'ValueType', 'any');
deps('validate') = {};
deps('examples') = {};
deps('tutorial') = {};
deps('sbc')      = {};
deps('pymc')     = {};
deps('compare')  = {'examples', 'pymc'};
deps('reports')  = {'examples', 'tutorial', 'sbc', 'compare'};
statusMap = containers.Map('KeyType', 'char', 'ValueType', 'char');

for k = 1:numel(stages)
    name = char(stages(k));
    fprintf('\n########## STAGE %d/%d: %s ##########\n', k, numel(stages), name);

    % ---- Prerequisite gate: skip consumers whose in-run producers failed --
    unmet = {};
    reqPrereqs = deps(name);
    for j = 1:numel(reqPrereqs)
        pr = reqPrereqs{j};
        if isKey(statusMap, pr) && ~strcmp(statusMap(pr), 'PASS')
            unmet{end+1} = pr; %#ok<AGROW>
        end
    end
    if ~isempty(unmet)
        message = sprintf('SKIPPED: prerequisite stage(s) did not pass: %s', ...
            strjoin(unmet, ', '));
        fprintf(2, '%s\n', message);
        statusMap(name) = 'SKIPPED';
        records(end+1) = makeRec(name, "SKIPPED", 0, message); %#ok<AGROW>
        fprintf('---- STAGE %s: SKIPPED ----\n', name);
        continue;
    end

    % ---- Fast-SBC/reports guard: *_fast SBC folders do not match the
    %      standard prefixes the report generators expect, so reports would
    %      silently reuse older standard SBC outputs. Block unless overridden.
    if strcmp(name, 'reports') && opts.UseFastSBC && ~opts.AllowFastReports
        message = ['SKIPPED: UseFastSBC=true produces non-standard SBC folder ' ...
            'names; report generators would silently use older standard SBC ' ...
            'outputs. Pass ''AllowFastReports'', true to override.'];
        fprintf(2, '%s\n', message);
        statusMap(name) = 'SKIPPED';
        records(end+1) = makeRec(name, "SKIPPED", 0, message); %#ok<AGROW>
        fprintf('---- STAGE %s: SKIPPED ----\n', name);
        continue;
    end

    % ---- Loud runtime warning before the full (non-fast) SBC stage --------
    if strcmp(name, 'sbc') && ~opts.UseFastSBC
        fprintf(2, ['\n*** WARNING: full SBC calibration (UseFastSBC=false) can take MANY HOURS.\n' ...
            '*** It runs LV(sharedfit), SIR, AP and LinearCascade3 at full replicate\n' ...
            '*** counts for manuscript-grade evidence. For a quick check instead, use\n' ...
            '*** run_full_evaluation(''UseFastSBC'', true) -- but then ''reports'' is skipped\n' ...
            '*** unless ''AllowFastReports'', true is also passed.\n\n']);
    end

    tStart = tic;                      % lives in THIS workspace; base-workspace
                                       % `clear` inside scripts cannot touch it.
    status = "PASS";
    message = "";
    try
        runStage(name, repoRoot, opts);
    catch ME
        status = "ERROR";
        message = string(ME.message);
        fprintf(2, 'STAGE %s FAILED: %s\n', name, ME.message);
        fprintf(2, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
        if ~opts.ContinueOnError
            records(end+1) = makeRec(name, status, toc(tStart), message); %#ok<AGROW>
            break;
        end
    end
    elapsed = toc(tStart);
    statusMap(name) = char(status);
    fprintf('---- STAGE %s: %s in %.1f s ----\n', name, status, elapsed);
    records(end+1) = makeRec(name, status, elapsed, message); %#ok<AGROW>
end

% ========================= SUMMARY =======================================
summary = struct2table(records, 'AsArray', true);
fprintf('\n==========================================================\n');
fprintf(' Evaluation summary\n');
fprintf('==========================================================\n');
disp(summary);

csvPath = fullfile(logDir, 'evaluation_summary.csv');
try
    writetable(summary, csvPath);
    fprintf('Summary written to: %s\n', csvPath);
catch ME
    fprintf(2, 'Could not write summary CSV: %s\n', ME.message);
end

if any(summary.Status == "ERROR")
    fprintf(2, '\nOne or more stages reported ERROR. See the diary log:\n  %s\n', diaryFile);
elseif any(summary.Status == "SKIPPED")
    fprintf(2, ['\nSome stages were SKIPPED because a prerequisite did not pass ' ...
        '(outputs may be incomplete). See the summary above and the diary log:\n  %s\n'], diaryFile);
else
    fprintf('\nAll executed stages completed without error.\n');
end
fprintf('Done: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss')));
end

% =========================================================================
% Stage dispatch
% =========================================================================
function runStage(name, repoRoot, opts)
switch lower(char(name))
    case 'validate'
        summary = validate_cuqdyn_repo(); %#ok<NASGU>

    case 'examples'   % Step 2
        % run_all_examples throws if any example fails; the caller's try/catch
        % records that, and per-example results are still saved to disk.
        summary = run_all_examples(); %#ok<NASGU>
        % Post-hoc UQ diagnostics for the main LV/SIR/AP/NF-kB runs (which
        % run_all_examples does not produce on its own). This writes
        % uq_diagnostics.xlsx into each result folder so the Supplementary
        % Information identifiability table is populated. It never throws.
        generate_uq_diagnostics(repoRoot);

    case 'tutorial'   % Step 3
        runScriptInBase(repoRoot, fullfile('EXAMPLES','LV'), ...
            'tutorial_LV_three_prediction_UQ_methods');

    case 'sbc'        % Step 4
        if opts.UseFastSBC
            sfx = '_fast';
        else
            sfx = '';
        end
        sbc = {
            fullfile('EXAMPLES','LV'),            ['SBC_LV2_FIM_vs_HybridCov_sharedfit' sfx]
            fullfile('EXAMPLES','SIR'),           ['SBC_SIR_FIM_vs_HybridCov' sfx]
            fullfile('EXAMPLES','AP'),            ['SBC_AP_FIM_vs_HybridCov' sfx]
            fullfile('EXAMPLES','LinearCascade'), ['SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit' sfx]
            };
        for i = 1:size(sbc,1)
            fprintf('  [sbc] %s\n', sbc{i,2});
            runScriptInBase(repoRoot, sbc{i,1}, sbc{i,2});
        end

    case 'pymc'       % Step 5
        % Defense-in-depth: force pure-Python mode before spawning Python.
        % The pymc scripts also set this, so it's redundant but harmless.
        setenv('PYTENSOR_FLAGS', 'cxx=');
        pymcDir = fullfile(repoRoot, 'pymc_matlab');
        if opts.RunUvSync
            runShell(pymcDir, 'uv sync', 'uv sync');
        end
        wrappers = {'run_bayes_lv','run_bayes_sir','run_bayes_ap','run_bayes_nfkb'};
        for i = 1:numel(wrappers)
            fprintf('  [pymc] %s\n', wrappers{i});
            runScriptInBase(repoRoot, 'pymc_matlab', wrappers{i});
        end

    case 'compare'    % Step 6
        runScriptInBase(repoRoot, 'pymc_matlab', 'compare_cuqdyn_pymc');

    case 'reports'    % Step 7
        pymcDir = fullfile(repoRoot, 'pymc_matlab');
        pyScripts = {
            'generate_results_latex_report.py'
            'generate_cuqdyn_pymc_comparison_report.py'
            'generate_combined_tutorial_latex.py'
            };
        for i = 1:numel(pyScripts)
            cmd = ['uv run python ' fullfile('..','scripts', pyScripts{i})];
            runShell(pymcDir, cmd, pyScripts{i});
        end

    otherwise
        error('run_full_evaluation:UnknownStage', 'Unknown stage: %s', name);
end
end

% =========================================================================
% Helpers
% =========================================================================
function runScriptInBase(repoRoot, relDir, scriptName)
% Run a (possibly `clear`-containing) script in the BASE workspace, isolated
% from the runner's own variables. Mirrors run_all_examples' approach.
targetDir = fullfile(repoRoot, relDir);
if exist(fullfile(targetDir, [scriptName '.m']), 'file') ~= 2 && ...
        exist(scriptName, 'file') ~= 2
    error('run_full_evaluation:MissingScript', ...
        'Script not found: %s in %s', scriptName, targetDir);
end
basePwd = pwd;
restoreDir = onCleanup(@() cd(basePwd));
cd(targetDir);
evalin('base', 'clear variables');
evalin('base', sprintf('run(''%s'');', escapeQuotes(fullfile(targetDir, [scriptName '.m']))));
end

function runShell(workDir, command, label)
% Run an OS shell command (e.g. uv) from workDir and echo its output.
basePwd = pwd;
restoreDir = onCleanup(@() cd(basePwd));
cd(workDir);
fprintf('  [shell] %s\n     %s\n', label, command);
[st, out] = system(command);
fprintf('%s\n', out);
if st ~= 0
    error('run_full_evaluation:ShellFailed', ...
        '"%s" exited with status %d.', label, st);
end
end

function s = escapeQuotes(s)
s = strrep(char(s), '''', '''''');
end

function rec = makeRec(name, status, elapsed, message)
rec = struct('Stage', string(name), 'Status', string(status), ...
    'ElapsedSeconds', elapsed, 'Message', string(message));
end

function names = allStageNames()
names = ["validate","examples","tutorial","sbc","pymc","compare","reports"];
end

function stages = resolveStages(requested)
all = allStageNames();
if isscalar(requested) && strcmpi(requested(1), "all")
    stages = all;
    return;
end
requested = lower(string(requested));
stages = strings(1,0);
for i = 1:numel(all)
    if any(requested == all(i))
        stages(end+1) = all(i); %#ok<AGROW>
    end
end
unknown = setdiff(requested, all);
if ~isempty(unknown)
    error('run_full_evaluation:UnknownStage', ...
        'Unknown stage(s): %s. Valid: %s', strjoin(unknown, ', '), strjoin(all, ', '));
end
if isempty(stages)
    error('run_full_evaluation:NoStages', 'No valid stages selected.');
end
end

function opts = parseOptions(varargin)
p = inputParser;
p.addParameter('Stages', "all");
p.addParameter('ContinueOnError', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('UseFastSBC', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('AllowFastReports', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('MeigoPath', '', @(x) ischar(x) || isstring(x));
p.addParameter('Ucrt64Bin', 'C:\msys64\ucrt64\bin', @(x) ischar(x) || isstring(x));
p.addParameter('RunUvSync', true, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
opts = p.Results;
opts.Stages = string(opts.Stages);
opts.ContinueOnError = logical(opts.ContinueOnError);
opts.UseFastSBC = logical(opts.UseFastSBC);
opts.AllowFastReports = logical(opts.AllowFastReports);
opts.RunUvSync = logical(opts.RunUvSync);
opts.MeigoPath = char(opts.MeigoPath);
opts.Ucrt64Bin = char(opts.Ucrt64Bin);
end
