function run_sbc_evaluation(repoRoot)
% RUN_SBC_EVALUATION  Autonomous SBC calibration + machine-aware report.
%
% Usage:
%   run_sbc_evaluation                 % auto-detect repo from mfile location
%   run_sbc_evaluation('/path/to/repo')
%
% This script:
%   1. Collects machine + MATLAB details
%   2. Locates/clones MEIGO64 if needed
%   3. Sets n_sim=15 in all SBC fast variants
%   4. Runs SIR_fast, LV_fast, LV_sharedfit_fast, AP_fast, LC3_sharedfit_fast
%   5. Extracts summary statistics from each result workspace
%   6. Restores modified SBC scripts to their original contents
%   7. Writes REPORTS/sbc_report_<timestamp>.md
%
% Works on Windows and Linux. Only the fast (local_after_global) SBC
% variants are executed; full eSS-loo variants are skipped for runtime.

% -------------------------------------------------------------------------
% 0. Paths and defaults
% -------------------------------------------------------------------------
if nargin < 1 || isempty(repoRoot)
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
end
fprintf('=== CUQDyn1_Plus Autonomous SBC Runner ===\n');
fprintf('Repo root: %s\n', repoRoot);

% Ensure src, EXAMPLES, unitTests on path
addpath(genpath(repoRoot));

% Locate or clone MEIGO64
meigoRoot = fullfile(repoRoot, 'MEIGO64-master');
if ~isfolder(meigoRoot)
    meigoPath = getenv('MEIGO64_PATH');
    if strlength(meigoPath) > 0 && isfolder(meigoPath)
        meigoRoot = meigoPath;
    else
        fprintf('MEIGO64 not found. Cloning from GitHub...\n');
        if system(sprintf('git clone --depth 1 https://github.com/gingproc-IIM-CSIC/MEIGO64.git "%s"', meigoRoot)) ~= 0
            error('Failed to clone MEIGO64. Please install manually.');
        end
    end
end
addpath(genpath(meigoRoot));
setenv('MEIGO64_PATH', meigoRoot);
fprintf('MEIGO64 root: %s\n', meigoRoot);

% -------------------------------------------------------------------------
% 1. Machine details
% -------------------------------------------------------------------------
machine = collectMachineInfo();
fprintf('\nMachine: %s\n  %s\n  %d cores, %s RAM\n', ...
    machine.os, machine.cpu, machine.cores, machine.ram);

% -------------------------------------------------------------------------
% 2. SBC script manifest
% -------------------------------------------------------------------------
nSimSbc = 15;  % fast calibration sample size
sbcScripts = {
    % name, folder, script file, workspace mat name
    'SIR_fast',       fullfile(repoRoot,'EXAMPLES','SIR'),           'SBC_SIR_FIM_vs_HybridCov_fast.m',               ''
    'LV_fast',        fullfile(repoRoot,'EXAMPLES','LV'),            'SBC_LV2_FIM_vs_HybridCov_fast.m',               'SBC_workspace.mat'
    'LV_sharedfit_fast',fullfile(repoRoot,'EXAMPLES','LV'),          'SBC_LV2_FIM_vs_HybridCov_sharedfit_fast.m',     'SBC_sharedfit_workspace.mat'
    'AP_fast',        fullfile(repoRoot,'EXAMPLES','AP'),            'SBC_AP_FIM_vs_HybridCov_fast.m',                ''
    'LC3_sharedfit_fast',fullfile(repoRoot,'EXAMPLES','LinearCascade'),'SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit_fast.m','SBC_LinearCascade3_sharedfit_workspace.mat'
};

% -------------------------------------------------------------------------
% 3. Patch n_sim -> 15 in all scripts
% -------------------------------------------------------------------------
fprintf('\n=== Patching n_sim to %d ===\n', nSimSbc);
originalSbcFiles = snapshotFiles(sbcScripts(:, 2), sbcScripts(:, 3));
restoreGuard = onCleanup(@() restoreFiles(originalSbcFiles));
for k = 1:size(sbcScripts,1)
    fpath = fullfile(sbcScripts{k,2}, sbcScripts{k,3});
    patchNsim(fpath, nSimSbc);
end

% -------------------------------------------------------------------------
% 4. Run each SBC script
% -------------------------------------------------------------------------
results = cell(size(sbcScripts,1), 1);
timings = zeros(size(sbcScripts,1), 1);

for k = 1:size(sbcScripts,1)
    name = sbcScripts{k,1};
    exDir = sbcScripts{k,2};
    script = sbcScripts{k,3};
    fprintf('\n########## [%d/%d] %s ##########\n', k, size(sbcScripts,1), name);
    t0 = tic;
    curPwd = pwd;
    try
        cd(exDir);
        run(script);
        elapsed = toc(t0);
        timings(k) = elapsed / 60;
        fprintf('[%s] completed in %.1f min\n', name, timings(k));
    catch ME
        elapsed = toc(t0);
        timings(k) = elapsed / 60;
        fprintf('[%s] ERROR after %.1f min: %s\n', name, timings(k), ME.message);
    end
    cd(curPwd);
    results{k} = name;  % filled in during extraction step below
end

% -------------------------------------------------------------------------
% 5. Extract summary statistics from result workspaces
% -------------------------------------------------------------------------
fprintf('\n=== Extracting summaries ===\n');
summaries = cell(size(sbcScripts,1), 1);

for k = 1:size(sbcScripts,1)
    name = sbcScripts{k,1};
    exDir = sbcScripts{k,2};
    wsBase = sbcScripts{k,4};
    summary = extractSbcSummary(exDir, name, wsBase);
    summaries{k} = summary;
end

% -------------------------------------------------------------------------
% 6. Restore patched SBC scripts
% -------------------------------------------------------------------------
fprintf('\n=== Restoring SBC scripts ===\n');
restoreFiles(originalSbcFiles);
delete(restoreGuard);

% -------------------------------------------------------------------------
% 7. Write markdown report
% -------------------------------------------------------------------------
reportDir = fullfile(repoRoot, 'REPORTS');
if ~exist(reportDir, 'dir'), mkdir(reportDir); end
ts = string(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
reportPath = fullfile(reportDir, sprintf('sbc_report_%s.md', ts));
writeReport(reportPath, machine, sbcScripts, timings, summaries, nSimSbc);
fprintf('\n=== REPORT WRITTEN ===\n  %s\n', reportPath);

end

% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function info = collectMachineInfo()
    info = struct();
    if ispc
        info.os = 'Windows';
        [~,cpu] = system('wmic cpu get name');
        cpu = strtrim(regexprep(cpu, 'Name\s*\r?\n?', ''));
        cpu = strtrim(regexprep(cpu, '\s+', ' '));
        info.cpu = cpu;
        [~,ram] = system('wmic computersystem get totalphysicalmemory');
        ram = regexp(ram, '\d+', 'match', 'once');
        if ~isempty(ram)
            info.ram = sprintf('%.0f GB', str2double(ram)/1e9);
        else
            info.ram = 'unknown';
        end
    else
        info.os = 'Linux';
        [~,cpu] = system('cat /proc/cpuinfo | grep "model name" | head -1');
        info.cpu = strtrim(regexprep(cpu, 'model name\s*:\s*', ''));
        [~,ram] = system('free -h | grep Mem');
        parts = strsplit(strtrim(ram));
        info.ram = parts{2};
    end
    info.cores = feature('numcores');
    info.matlab = sprintf('MATLAB R%s (%s)', version('-release'), version);
    info.matlab_version = version;
    info.matlab_release = version('-release');
    info.toolboxes = struct(...
        'stats', license('test','statistics_toolbox'), ...
        'optim', license('test','optimization_toolbox'), ...
        'parallel', license('test','distrib_computing_toolbox'));
    [~,info.hostname] = system('hostname');
    info.hostname = strtrim(info.hostname);
end

function patchNsim(filePath, nSimVal)
    if ~exist(filePath, 'file')
        warning('SBC script not found: %s', filePath);
        return;
    end
    txt = fileread(filePath);
    % Replace n_sim = XX (with any spacing) or config.n_sim = XX
    txt = regexprep(txt, 'n_sim\s*=\s*\d+', sprintf('n_sim = %d', nSimVal));
    txt = regexprep(txt, 'config\.n_sim\s*=\s*\d+', sprintf('config.n_sim = %d', nSimVal));
    fid = fopen(filePath, 'w');
    if fid < 0, error('Cannot write %s', filePath); end
    fprintf(fid, '%s', txt);
    fclose(fid);
end

function originals = snapshotFiles(folders, files)
    n = numel(files);
    originals = struct('path', cell(n, 1), 'text', cell(n, 1), 'exists', cell(n, 1));
    for k = 1:n
        fpath = fullfile(folders{k}, files{k});
        originals(k).path = fpath;
        originals(k).exists = exist(fpath, 'file') == 2;
        if originals(k).exists
            originals(k).text = fileread(fpath);
        else
            originals(k).text = '';
        end
    end
end

function restoreFiles(originals)
    for k = 1:numel(originals)
        if ~originals(k).exists
            continue;
        end
        fid = fopen(originals(k).path, 'w');
        if fid < 0
            warning('run_sbc_evaluation:RestoreFailed', ...
                'Could not restore %s', originals(k).path);
            continue;
        end
        fprintf(fid, '%s', originals(k).text);
        fclose(fid);
    end
end

function summary = extractSbcSummary(exDir, name, wsBase)
    summary = struct();
    summary.name = name;
    summary.status = 'UNKNOWN';
    summary.fim_cov_mean = NaN;
    summary.fim_cov_sd = NaN;
    summary.fim_simult = NaN;
    summary.hyb_cov_mean = NaN;
    summary.hyb_cov_sd = NaN;
    summary.hyb_simult = NaN;
    summary.nominal = NaN;
    summary.n_success = NaN;
    summary.n_sim = NaN;
    summary.fim_marginal_std = [];
    summary.hyb_marginal_std = [];

    % find newest SBC result dir
    resultsPattern = 'SBC_Results_*';
    d = dir(fullfile(exDir, resultsPattern));
    d = d([d.isdir]);
    if isempty(d)
        summary.status = 'NO_RESULTS_DIR';
        return;
    end
    [~, idx] = max([d.datenum]);
    rd = fullfile(d(idx).folder, d(idx).name);

    % find workspace mat
    wsm = [];
    if ~isempty(wsBase)
        wsCandidate = fullfile(rd, wsBase);
        if exist(wsCandidate, 'file'), wsm = wsCandidate; end
    end
    if isempty(wsm)
        % search for any workspace .mat
        mats = dir(fullfile(rd, '*workspace*.mat'));
        if isempty(mats)
            mats = dir(fullfile(rd, '*.mat'));
        end
        if ~isempty(mats)
            wsm = fullfile(mats(1).folder, mats(1).name);
        end
    end
    if isempty(wsm)
        summary.status = 'NO_WORKSPACE_MAT';
        return;
    end

    try
        S = load(wsm);
    catch
        summary.status = 'LOAD_FAILED';
        return;
    end

    % route by model based on which fields exist
    if isfield(S, 'nominal_coverage')
        summary.nominal = S.nominal_coverage * 100;
    end

    % ---- SIR (has cov S / cov R per replicate but separate arrays) ----
    % Fallback: SIR workspace doesn't save ptwise arrays, only the
    % final fprintf summary.  We try to load covered_fim/hyb.
    if isfield(S, 'covered_fim') && isfield(S, 'covered_hyb')
        cf = S.covered_fim;
        ch = S.covered_hyb;
        ok = true(size(cf,1),1);
        if isfield(S, 'success'), ok = S.success; end
        nStates = size(cf, 2);  % n_eval = (m-1)*n_unobs
        if nStates > 1
            % multiple hidden states: compute per-state then average
            nHalf = nStates / 2;
            pf = [mean(cf(ok,1:nHalf),2,'omitnan'), mean(cf(ok,nHalf+1:end),2,'omitnan')];
            ph = [mean(ch(ok,1:nHalf),2,'omitnan'), mean(ch(ok,nHalf+1:end),2,'omitnan')];
        else
            pf = cf(ok, :);
            ph = ch(ok, :);
        end
        pf_all = mean(pf, 2, 'omitnan');
        ph_all = mean(ph, 2, 'omitnan');
        summary.fim_cov_mean = mean(pf_all, 'omitnan') * 100;
        summary.fim_cov_sd   = std(pf_all, 'omitnan') * 100;
        summary.hyb_cov_mean = mean(ph_all, 'omitnan') * 100;
        summary.hyb_cov_sd   = std(ph_all, 'omitnan') * 100;
        % simultaneous: per-replicate, all time points for each state
        if nStates > 1
            simFim = all(cf(ok,1:nHalf),2) & all(cf(ok,nHalf+1:end),2);
            simHyb = all(ch(ok,1:nHalf),2) & all(ch(ok,nHalf+1:end),2);
        else
            simFim = all(cf(ok,:), 2);
            simHyb = all(ch(ok,:), 2);
        end
        summary.fim_simult = mean(simFim, 'omitnan') * 100;
        summary.hyb_simult = mean(simHyb, 'omitnan') * 100;
        summary.n_success = sum(ok);
        summary.n_sim = numel(ok);
        summary.status = 'OK';
    end

    % Try to get ptwise arrays if they exist
    if isfield(S, 'ptwise_fim') && isfield(S, 'ptwise_hyb')
        summary.fim_cov_mean = mean(S.ptwise_fim, 'omitnan') * 100;
        summary.fim_cov_sd   = std(S.ptwise_fim, 'omitnan') * 100;
        summary.hyb_cov_mean = mean(S.ptwise_hyb, 'omitnan') * 100;
        summary.hyb_cov_sd   = std(S.ptwise_hyb, 'omitnan') * 100;
        if isfield(S, 'simult_fim'), summary.fim_simult = mean(S.simult_fim)*100; end
        if isfield(S, 'simult_hyb'), summary.hyb_simult = mean(S.simult_hyb)*100; end
        summary.status = 'OK';
    end

    % marginal std devs
    if isfield(S, 'D_fim_all')
        summary.fim_marginal_std = mean(S.D_fim_all, 1, 'omitnan');
    end
    if isfield(S, 'D_hyb_all')
        summary.hyb_marginal_std = mean(S.D_hyb_all, 1, 'omitnan');
    end

    % nominal coverage
    if isnan(summary.nominal) && isfield(S, 'nominal_coverage')
        summary.nominal = S.nominal_coverage * 100;
    end

    % width information if available
    if isfield(S, 'width_fim')
        summary.fim_band_width = mean(S.width_fim(:), 'omitnan');
    end
    if isfield(S, 'width_hyb')
        summary.hyb_band_width = mean(S.width_hyb(:), 'omitnan');
    end

    fprintf('  %s: status=%s nominal=%.0f%%\n', name, summary.status, summary.nominal);
end

function writeReport(reportPath, machine, sbcScripts, timings, summaries, nSim)
    fid = fopen(reportPath, 'w');
    if fid < 0, error('Cannot write %s', reportPath); end
    c = onCleanup(@() fclose(fid));

    w = @(varargin) fprintf(fid, varargin{:});

    w('# CUQDyn1_Plus --- Autonomous SBC Calibration Report\n\n');
    w('**Generated:** %s\n\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    w('**N (replicates per model):** %d\n\n', nSim);

    % --- Machine info ---
    w('## 1. Machine\n\n');
    w('| Property | Value |\n');
    w('|---|---|\n');
    w('| Hostname | %s |\n', machine.hostname);
    w('| OS | %s |\n', machine.os);
    w('| CPU | %s |\n', machine.cpu);
    w('| Cores | %d logical |\n', machine.cores);
    w('| RAM | %s |\n', machine.ram);
    w('| MATLAB | %s (release %s) |\n', machine.matlab_version, machine.matlab_release);
    w('| Stats Toolbox | %d |\n', machine.toolboxes.stats);
    w('| Optim Toolbox | %d |\n', machine.toolboxes.optim);
    w('| Parallel Toolbox | %d |\n', machine.toolboxes.parallel);
    w('\n');

    % --- Runtime ---
    w('## 2. Runtimes\n\n');
    w('| Script | Time (min) |\n');
    w('|---|---|\n');
    for k = 1:numel(timings)
        w('| %s | %.1f |\n', sbcScripts{k,1}, timings(k));
    end
    w('\n');

    % --- Coverage summary ---
    w('## 3. Coverage Results\n\n');
    w('Coverage is evaluated against the noise-free true trajectory for ');
    w('unobserved states. Nominal coverage is (1 - 2*alp).\n\n');

    for k = 1:numel(summaries)
        s = summaries{k};
        w('### %s\n\n', s.name);
        if ~strcmp(s.status, 'OK')
            w('**Status: %s** (no summary available)\n\n', s.status);
            continue;
        end
        w('| Metric | FIM | HybridCov |\n');
        w('|---|---|---|\n');
        if ~isnan(s.nominal)
            w('| Nominal | %.0f%% | %.0f%% |\n', s.nominal, s.nominal);
        end
        w('| Mean pointwise coverage | %.1f%% | %.1f%% |\n', s.fim_cov_mean, s.hyb_cov_mean);
        if ~isnan(s.fim_cov_sd)
            w('| Std pointwise coverage  | %.1f%% | %.1f%% |\n', s.fim_cov_sd, s.hyb_cov_sd);
        end
        if ~isnan(s.fim_simult)
            w('| Simultaneous coverage   | %.1f%% | %.1f%% |\n', s.fim_simult, s.hyb_simult);
        end
        if isfield(s, 'fim_band_width') && ~isnan(s.fim_band_width)
            w('| Mean band width         | %.4f | %.4f |\n', s.fim_band_width, s.hyb_band_width);
        end
        if ~isempty(s.fim_marginal_std)
            w('| Mean marginal std devs  | %s | %s |\n', ...
                num2str(s.fim_marginal_std, '%.4g '), ...
                num2str(s.hyb_marginal_std, '%.4g '));
        end
        if ~isnan(s.n_success)
            w('| Successful replicates   | %d / %d |\n', s.n_success, s.n_sim);
        end
        w('\n');
    end

    % --- Notes ---
    w('## 4. Notes\n\n');
    w('- All SBC scripts used the `local_after_global` refit strategy (lsqnonlin warm-started\n');
    w('  from the full-data eSS solution).\n');
    w('- RNG seed = 42. Both methods receive identical synthetic datasets within each replicate.\n');
    w('- Coverage is pointwise (per-time-point average) unless labelled simultaneous.\n');
    w('- Simultaneous coverage = fraction of replicates where *all* time points are covered.\n');
    w('- Shared-fit variants (LV, LC3) compare FIM and HybridCov from the same optimizer run.\n');
    w('- N=%d replicates per model; sampling error ~> %%.1f pp for pointwise coverage.\n', ...
        nSim, 100/sqrt(nSim));
    w('- Full SBC at N=50-250 is recommended for publication-grade evidence.\n');
    w('- This report was generated autonomously --- no manual edits.\n');

    fprintf('Report written: %s\n', reportPath);
end
