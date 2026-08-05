%% compare_cuqdyn_pymc.m
% Build common CUQDyn-vs-PyMC comparison tables and overlay plots.
%
% Run from the repository root or from pymc_matlab/. The script does not run
% CUQDyn or PyMC; it summarizes existing result folders.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(scriptDir);
if ~isfolder(fullfile(repoRoot, 'EXAMPLES'))
    repoRoot = pwd;
end

timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
outDir = fullfile(scriptDir, 'results', 'comparison', timestamp);
if ~isfolder(outDir)
    mkdir(outDir);
end

configs = comparisonConfigs(repoRoot);

parameterRows = table();
bandRows = table();

fprintf('CUQDyn/PyMC comparison output:\n  %s\n\n', outDir);

for i = 1:numel(configs)
    cfg = configs(i);
    fprintf('=== %s ===\n', cfg.model);

    pymcDir = fullfile(scriptDir, 'results', cfg.pymcSubdir);
    if ~isfolder(pymcDir)
        warning('Missing PyMC results for %s: %s', cfg.model, pymcDir);
        continue;
    end

    pymcParam = summarizePyMCParameters(cfg, pymcDir);
    parameterRows = [parameterRows; pymcParam]; %#ok<AGROW>

    pymcTraj = loadPyMCTrajectories(cfg, pymcDir);
    pymcBands = summarizeTrajectoryBands(cfg, 'PyMC ABC-SMC', ...
        pymcTraj.t, pymcTraj.mean, pymcTraj.lower, pymcTraj.upper, pymcTraj.observed);
    bandRows = [bandRows; pymcBands]; %#ok<AGROW>

    cuqRuns = locateCUQDynRuns(cfg);
    for r = 1:numel(cuqRuns)
        if isempty(cuqRuns(r).matFile)
            warning('Missing CUQDyn %s result for %s.', cuqRuns(r).method, cfg.model);
            continue;
        end
        C = load(cuqRuns(r).matFile, 'results');
        R = C.results;
        cuqParam = summarizeCUQDynParameters(cfg, cuqRuns(r).method, R);
        parameterRows = [parameterRows; cuqParam]; %#ok<AGROW>

        observed = observedMatrixFromCUQDyn(R);
        cuqBands = summarizeTrajectoryBands(cfg, cuqRuns(r).method, ...
            R.times(:), R.media_tot, R.UQ_lower, R.UQ_upper, observed);
        bandRows = [bandRows; cuqBands]; %#ok<AGROW>
    end

    plotModelComparison(cfg, pymcTraj, cuqRuns, outDir);
end

parameterFileCsv = fullfile(outDir, 'parameter_summary_comparison.csv');
parameterFileXlsx = fullfile(outDir, 'parameter_summary_comparison.xlsx');
bandFileCsv = fullfile(outDir, 'trajectory_band_summary_comparison.csv');
bandFileXlsx = fullfile(outDir, 'trajectory_band_summary_comparison.xlsx');

writetable(parameterRows, parameterFileCsv);
writetable(parameterRows, parameterFileXlsx);
writetable(bandRows, bandFileCsv);
writetable(bandRows, bandFileXlsx);

fprintf('\nSaved shared comparison tables:\n');
fprintf('  %s\n', parameterFileCsv);
fprintf('  %s\n', bandFileCsv);
fprintf('\nSaved overlay plots in:\n  %s\n', outDir);

%% Local functions ---------------------------------------------------------

function configs = comparisonConfigs(repoRoot)
nfkbParamNames = arrayfun(@(k) sprintf('p%d', k), 1:29, 'UniformOutput', false);
nfkbStateNames = arrayfun(@(k) sprintf('y%d', k), 1:15, 'UniformOutput', false);
nfkbObservedIdx = [1 2 3 5 7 9 11 12 13 15];
nfkbObservedNames = arrayfun(@(k) sprintf('y%d', k), nfkbObservedIdx, 'UniformOutput', false);
nfkbTrajectoryFiles = arrayfun(@(k) sprintf('y%d_trajectories.csv', k), 1:15, 'UniformOutput', false);

configs = struct( ...
    'model', "LV", ...
    'exampleDir', fullfile(repoRoot, 'EXAMPLES', 'LV'), ...
    'pymcSubdir', 'lv', ...
    'paramNames', {{'alpha','beta','delta','gamma'}}, ...
    'trueValues', [0.5, 0.02, 0.02, 0.5], ...
    'stateNames', {{'prey','predator'}}, ...
    'pymcMeanColumns', {{'prey','predator'}}, ...
    'pymcObservedColumns', {{'prey_observed'}}, ...
    'pymcTrajectoryFiles', {{'prey_trajectories.csv','predator_trajectories.csv'}}, ...
    'observedIdx', 1, ...
    'cuqPatterns', {{'Results_LV2_CUQDyn1_Plus_*', 'Results_LV2_HybridCov_*'}}, ...
    'cuqMatFiles', {{'CUQDyn1_Plus_results.mat','CUQDyn1_Plus_HybridCov_results.mat'}}, ...
    'cuqMethods', {{'CUQDyn1_Plus FIM','CUQDyn1_Plus HybridCov'}} ...
    );

configs(end+1) = struct( ...
    'model', "SIR", ...
    'exampleDir', fullfile(repoRoot, 'EXAMPLES', 'SIR'), ...
    'pymcSubdir', 'sir', ...
    'paramNames', {{'beta','gamma'}}, ...
    'trueValues', [0.002, 0.5], ...
    'stateNames', {{'susceptible','infected','recovered'}}, ...
    'pymcMeanColumns', {{'susceptible','infected','recovered'}}, ...
    'pymcObservedColumns', {{'infected_observed'}}, ...
    'pymcTrajectoryFiles', {{'susceptible_trajectories.csv','infected_trajectories.csv','recovered_trajectories.csv'}}, ...
    'observedIdx', 2, ...
    'cuqPatterns', {{'Results_SIR_CUQDyn1Plus_*', 'Results_SIR_HybridCov_*'}}, ...
    'cuqMatFiles', {{'CUQDyn1_Plus_results.mat','CUQDyn1_Plus_HybridCov_results.mat'}}, ...
    'cuqMethods', {{'CUQDyn1_Plus FIM','CUQDyn1_Plus HybridCov'}} ...
    );

configs(end+1) = struct( ...
    'model', "AP", ...
    'exampleDir', fullfile(repoRoot, 'EXAMPLES', 'AP'), ...
    'pymcSubdir', 'ap', ...
    'paramNames', {{'p1','p2','p3','p4','p5'}}, ...
    'trueValues', [5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05], ...
    'stateNames', {{'y1','y2','y3','y4','y5'}}, ...
    'pymcMeanColumns', {{'y1','y2','y3','y4','y5'}}, ...
    'pymcObservedColumns', {{'y1','y2','y3','y4'}}, ...
    'pymcTrajectoryFiles', {{'y1_trajectories.csv','y2_trajectories.csv','y3_trajectories.csv','y4_trajectories.csv','y5_trajectories.csv'}}, ...
    'observedIdx', [1 2 3 4], ...
    'cuqPatterns', {{'Results_AP_partobs1_4_*', 'Results_AP_HybridCov_partobs1_4_*'}}, ...
    'cuqMatFiles', {{'CUQDyn1_Plus_results.mat','CUQDyn1_Plus_HybridCov_results.mat'}}, ...
    'cuqMethods', {{'CUQDyn1_Plus FIM','CUQDyn1_Plus HybridCov'}} ...
    );

configs(end+1) = struct( ...
    'model', "NFKB", ...
    'exampleDir', fullfile(repoRoot, 'EXAMPLES', 'NFKB'), ...
    'pymcSubdir', 'nfkb', ...
    'paramNames', {nfkbParamNames}, ...
    'trueValues', [0.5 0.2 0.1 1.0 0.1 5e-7 0.0001 0.0004 0.5 0.0001 0.00002 5e-7 0.0001 0.0004 0.5 0.0003 0.0025 0.1 0.0015 0.000025 0.000125 5.0 0.0025 0.01 0.001 0.0005 5e-7 0.0001 0.0004], ...
    'stateNames', {nfkbStateNames}, ...
    'pymcMeanColumns', {nfkbStateNames}, ...
    'pymcObservedColumns', {nfkbObservedNames}, ...
    'pymcTrajectoryFiles', {nfkbTrajectoryFiles}, ...
    'observedIdx', nfkbObservedIdx, ...
    'cuqPatterns', {{'Results_NFKB_*', 'Results_NFKB_*'}}, ...
    'cuqMatFiles', {{'CUQDyn1_Plus_results.mat','CUQDyn1_Plus_HybridCov_results.mat'}}, ...
    'cuqMethods', {{'CUQDyn1_Plus FIM','CUQDyn1_Plus HybridCov'}} ...
    );
end

function T = summarizePyMCParameters(cfg, pymcDir)
post = readtable(fullfile(pymcDir, 'posterior_samples.csv'));
n = numel(cfg.paramNames);
T = baseParameterTable(n);
for i = 1:n
    name = cfg.paramNames{i};
    samples = post.(name);
    T.Model(i) = cfg.model;
    T.Method(i) = "PyMC ABC-SMC";
    T.Parameter(i) = string(name);
    T.TrueValue(i) = cfg.trueValues(i);
    T.Estimate(i) = mean(samples, 'omitnan');
    T.StdDev(i) = std(samples, 'omitnan');
    q = quantile(samples, [0.025 0.975]);
    T.IntervalLower(i) = q(1);
    T.IntervalUpper(i) = q(2);
    T.RelErrPercent(i) = relativeError(T.Estimate(i), T.TrueValue(i));
end
end

function T = summarizeCUQDynParameters(cfg, methodName, R)
n = numel(cfg.paramNames);
T = baseParameterTable(n);
theta = R.parameters_init(:)';
stdTheta = nan(1, n);
if isfield(R, 'Cov_p') && isequal(size(R.Cov_p), [n n])
    stdTheta = sqrt(max(diag(R.Cov_p), 0))';
end
z = 1.96;
for i = 1:n
    T.Model(i) = cfg.model;
    T.Method(i) = string(methodName);
    T.Parameter(i) = string(cfg.paramNames{i});
    T.TrueValue(i) = cfg.trueValues(i);
    T.Estimate(i) = theta(i);
    T.StdDev(i) = stdTheta(i);
    T.IntervalLower(i) = theta(i) - z * stdTheta(i);
    T.IntervalUpper(i) = theta(i) + z * stdTheta(i);
    T.RelErrPercent(i) = relativeError(theta(i), cfg.trueValues(i));
end
end

function T = baseParameterTable(n)
T = table(strings(n,1), strings(n,1), strings(n,1), nan(n,1), nan(n,1), ...
    nan(n,1), nan(n,1), nan(n,1), nan(n,1), ...
    'VariableNames', {'Model','Method','Parameter','TrueValue','Estimate', ...
    'StdDev','IntervalLower','IntervalUpper','RelErrPercent'});
end

function value = relativeError(estimate, truth)
if isnan(truth) || truth == 0
    value = NaN;
else
    value = 100 * abs(estimate - truth) / abs(truth);
end
end

function runs = locateCUQDynRuns(cfg)
runs = struct('method', {}, 'dir', {}, 'matFile', {});
for i = 1:numel(cfg.cuqPatterns)
    d = latestMatchingDir(cfg.exampleDir, cfg.cuqPatterns{i}, cfg.cuqMatFiles{i});
    matFile = "";
    if strlength(d) > 0
        matFile = string(fullfile(d, cfg.cuqMatFiles{i}));
    end
    runs(end+1) = struct('method', cfg.cuqMethods{i}, 'dir', d, 'matFile', matFile); %#ok<AGROW>
end
end

function d = latestMatchingDir(parentDir, pattern, requiredFile)
matches = dir(fullfile(parentDir, pattern));
matches = matches([matches.isdir]);
keep = false(size(matches));
for i = 1:numel(matches)
    keep(i) = isfile(fullfile(matches(i).folder, matches(i).name, requiredFile));
end
matches = matches(keep);
if isempty(matches)
    d = "";
    return;
end
[~, idx] = max([matches.datenum]);
d = string(fullfile(matches(idx).folder, matches(idx).name));
end

function observed = observedMatrixFromCUQDyn(R)
observed = nan(size(R.media_tot));
if isempty(R.observed_idx)
    return;
end
observed(:, R.observed_idx) = R.observed_data;
end

function traj = loadPyMCTrajectories(cfg, pymcDir)
meanTraj = readtable(fullfile(pymcDir, 'mean_trajectory.csv'));
obs = readtable(fullfile(pymcDir, 'observed_data_out.csv'));
t = meanTraj.t;
nStates = numel(cfg.stateNames);
meanY = nan(numel(t), nStates);
lower = nan(numel(t), nStates);
upper = nan(numel(t), nStates);
observed = nan(numel(t), nStates);

for j = 1:nStates
    meanY(:, j) = meanTraj.(cfg.pymcMeanColumns{j});
    M = readmatrix(fullfile(pymcDir, cfg.pymcTrajectoryFiles{j}), 'NumHeaderLines', 1);
    lower(:, j) = quantile(M, 0.025, 2);
    upper(:, j) = quantile(M, 0.975, 2);
end
for j = 1:numel(cfg.observedIdx)
    observed(:, cfg.observedIdx(j)) = obs.(cfg.pymcObservedColumns{j});
end

traj = struct('t', t, 'mean', meanY, 'lower', lower, 'upper', upper, 'observed', observed);
end

function T = summarizeTrajectoryBands(cfg, methodName, ~, meanY, lower, upper, observed)
nStates = numel(cfg.stateNames);
T = table(strings(nStates,1), strings(nStates,1), strings(nStates,1), ...
    nan(nStates,1), nan(nStates,1), nan(nStates,1), nan(nStates,1), ...
    'VariableNames', {'Model','Method','State','MeanBandWidth','MedianBandWidth', ...
    'ObservedCoveragePercent','RMSEObservedStates'});

for j = 1:nStates
    bandWidth = upper(:, j) - lower(:, j);
    obs = observed(:, j);
    hasObs = isfinite(obs);
    T.Model(j) = cfg.model;
    T.Method(j) = string(methodName);
    T.State(j) = string(cfg.stateNames{j});
    T.MeanBandWidth(j) = mean(bandWidth, 'omitnan');
    T.MedianBandWidth(j) = median(bandWidth, 'omitnan');
    if any(hasObs)
        T.ObservedCoveragePercent(j) = 100 * mean(obs(hasObs) >= lower(hasObs, j) & obs(hasObs) <= upper(hasObs, j));
        T.RMSEObservedStates(j) = sqrt(mean((meanY(hasObs, j) - obs(hasObs)).^2));
    end
end
end

function plotModelComparison(cfg, pymcTraj, cuqRuns, outDir)
nStates = numel(cfg.stateNames);

cuqData = {};
for r = 1:numel(cuqRuns)
    if strlength(cuqRuns(r).matFile) == 0
        continue;
    end
    S = load(cuqRuns(r).matFile, 'results');
    cuqData{end+1} = struct('method', cuqRuns(r).method, 'results', S.results); %#ok<AGROW>
end

methodNames = [{'PyMC ABC-SMC'}, cellfun(@(x) x.method, cuqData, 'UniformOutput', false)];
nMethods = numel(methodNames);
colors = lines(nMethods);

maxRowsPerFigure = 5;
chunks = arrayfun(@(s) s:min(s+maxRowsPerFigure-1, nStates), ...
    1:maxRowsPerFigure:nStates, 'UniformOutput', false);

for chunkIdx = 1:numel(chunks)
    stateIdx = chunks{chunkIdx};
    nRows = numel(stateIdx);
    figHeight = max(320, 220*nRows);
    fig = figure('Name', char(cfg.model + " CUQDyn vs PyMC"), 'Color', 'w', ...
        'Position', [50 50 430*nMethods figHeight]);
    tl = tiledlayout(nRows, nMethods, 'Padding', 'compact', 'TileSpacing', 'compact');

    for row = 1:nRows
        j = stateIdx(row);
        yMin = min([pymcTraj.lower(:,j); pymcTraj.mean(:,j); pymcTraj.upper(:,j)], [], 'omitnan');
        yMax = max([pymcTraj.lower(:,j); pymcTraj.mean(:,j); pymcTraj.upper(:,j)], [], 'omitnan');
        for r = 1:numel(cuqData)
            R = cuqData{r}.results;
            yMin = min(yMin, min([R.UQ_lower(:,j); R.media_tot(:,j); R.UQ_upper(:,j)], [], 'omitnan'));
            yMax = max(yMax, max([R.UQ_lower(:,j); R.media_tot(:,j); R.UQ_upper(:,j)], [], 'omitnan'));
        end
        obs = pymcTraj.observed(:, j);
        if any(isfinite(obs))
            yMin = min(yMin, min(obs, [], 'omitnan'));
            yMax = max(yMax, max(obs, [], 'omitnan'));
        end
        if ~isfinite(yMin) || ~isfinite(yMax) || yMin == yMax
            yMin = 0; yMax = 1;
        end
        pad = 0.05 * max(yMax - yMin, eps);
        yLimits = [yMin - pad, yMax + pad];

        for col = 1:nMethods
            nexttile; hold on;
            c = colors(col, :);
            if col == 1
                plotBand(pymcTraj.t, pymcTraj.lower(:,j), pymcTraj.upper(:,j), c, 0.22);
                plot(pymcTraj.t, pymcTraj.mean(:,j), '-', 'Color', c, 'LineWidth', 1.8, ...
                    'DisplayName', 'mean');
            else
                R = cuqData{col-1}.results;
                plotBand(R.times(:), R.UQ_lower(:,j), R.UQ_upper(:,j), c, 0.18);
                plot(R.times(:), R.media_tot(:,j), '-', 'Color', c, 'LineWidth', 1.7, ...
                    'DisplayName', 'mean');
            end
            if any(isfinite(obs))
                scatter(pymcTraj.t, obs, 12, 'k', 'filled', 'DisplayName', 'observed');
            end
            ylim(yLimits);
            title(sprintf('%s | %s', cfg.stateNames{j}, methodNames{col}), ...
                'Interpreter', 'none', 'FontSize', 8);
            xlabel('time'); ylabel('state value'); grid on;
            if row == 1 && col == 1
                legend('Location', 'best', 'Interpreter', 'none', 'FontSize', 7);
            end
            hold off;
        end
    end
    title(tl, sprintf('%s: CUQDyn vs PyMC predictive bands, states %d-%d', ...
        cfg.model, stateIdx(1), stateIdx(end)), 'Interpreter', 'none');

    if isscalar(chunks)
        baseName = sprintf('%s_cuqdyn_vs_pymc_side_by_side', lower(cfg.model));
    else
        baseName = sprintf('%s_cuqdyn_vs_pymc_side_by_side_states%02d_%02d', ...
            lower(cfg.model), stateIdx(1), stateIdx(end));
    end
    exportgraphics(fig, fullfile(outDir, [baseName '.png']), 'Resolution', 220);
    try
        exportgraphics(fig, fullfile(outDir, [baseName '.pdf']), 'ContentType', 'vector');
    catch ME
        warning('compare_cuqdyn_pymc:PDFExportFailed', ...
            'Could not export %s.pdf: %s', baseName, ME.message);
    end
    try
        print(fig, fullfile(outDir, [baseName '.eps']), '-depsc', '-painters');
    catch ME
        warning('compare_cuqdyn_pymc:EPSExportFailed', ...
            'Could not export %s.eps: %s', baseName, ME.message);
    end
    savefig(fig, fullfile(outDir, [baseName '.fig']));
    close(fig);
end
end

function plotBand(t, lo, hi, color, alphaValue)
x = [t(:); flipud(t(:))];
y = [lo(:); flipud(hi(:))];
patch(x, y, color, 'FaceAlpha', alphaValue, 'EdgeColor', 'none', 'HandleVisibility', 'off');
end
