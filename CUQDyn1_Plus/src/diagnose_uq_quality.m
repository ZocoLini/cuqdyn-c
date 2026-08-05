function diagnostics = diagnose_uq_quality(results, resultDir, param_names, state_names, lb_params, ub_params)
%DIAGNOSE_UQ_QUALITY  Post-hoc diagnostics for CUQDyn1_Plus UQ results.
%
%   diagnostics = diagnose_uq_quality(results, resultDir)
%   diagnostics = diagnose_uq_quality(results, resultDir, param_names, state_names)
%   diagnostics = diagnose_uq_quality(..., lb_params, ub_params)
%
%   This function does not recompute fits, LOO refits, sensitivities, or
%   Jacobians. It inspects fields already present in CUQDyn1_Plus and
%   CUQDyn1_Plus_HybridCov results and writes compact diagnostic tables to
%   uq_diagnostics.xlsx and uq_diagnostics.mat.
%
% Diagnostics include covariance eigenvalues/conditioning, residual variance
% with and without the initial row, marginal parameter standard deviations,
% parameter correlations, optional bound-proximity flags, and HybridCov-specific
% FIM/LOO/Hybrid marginal-scale comparisons when available.

if nargin < 3 || isempty(param_names)
    param_names = arrayfun(@(j) sprintf('Param%d', j), 1:results.n_params, 'UniformOutput', false);
end
if nargin < 4 || isempty(state_names)
    state_names = arrayfun(@(j) sprintf('State%d', j), 1:results.nstates, 'UniformOutput', false);
end
if nargin < 5
    lb_params = [];
end
if nargin < 6
    ub_params = [];
end

resultDir = char(resultDir);
if ~exist(resultDir, 'dir')
    mkdir(resultDir);
end

param_names = param_names(:);
state_names = state_names(:);
if numel(param_names) ~= results.n_params
    error('diagnose_uq_quality:ParamNameMismatch', ...
        'param_names must contain one name per parameter.');
end
if numel(state_names) ~= results.nstates
    error('diagnose_uq_quality:StateNameMismatch', ...
        'state_names must contain one name per state.');
end

Cov_p = results.Cov_p;
Cov_p = (Cov_p + Cov_p') / 2;
covEig = eig(Cov_p);
paramStd = sqrt(max(diag(Cov_p), 0));
paramEst = results.parameters_init(:);

relParamStd = NaN(size(paramStd));
nonzero = abs(paramEst) > eps;
relParamStd(nonzero) = paramStd(nonzero) ./ abs(paramEst(nonzero));

Corr_p = safe_corr_from_cov(Cov_p);
offDiagCorr = Corr_p(~eye(size(Corr_p)));
maxAbsCorr = max(abs(offDiagCorr), [], 'omitnan');

fimRank = NaN;
fimConditionNumber = NaN;
fimWeakDirections = NaN;
fimMaxWeakFraction = NaN;
fimAnyUnreliableBands = false;
if isfield(results, 'diagnostics') && isfield(results.diagnostics, 'fim')
    fimDiag = results.diagnostics.fim;
    if isfield(fimDiag, 'rank'), fimRank = fimDiag.rank; end
    if isfield(fimDiag, 'condition_number'), fimConditionNumber = fimDiag.condition_number; end
    if isfield(fimDiag, 'n_weak_directions'), fimWeakDirections = fimDiag.n_weak_directions; end
    if isfield(fimDiag, 'max_weak_fraction'), fimMaxWeakFraction = fimDiag.max_weak_fraction; end
    if isfield(fimDiag, 'any_unreliable_bands'), fimAnyUnreliableBands = fimDiag.any_unreliable_bands; end
end

residuals = results.observed_data - results.media_tot(:, results.observed_idx);
residuals_no_ic = residuals(2:end, :);
sigma2_all = sum(residuals(:).^2) / max(numel(residuals) - results.n_params, 1);
sigma2_no_ic = sum(residuals_no_ic(:).^2) / max(numel(residuals_no_ic) - results.n_params, 1);

obsStateNames = state_names(results.observed_idx);
resRmse = sqrt(mean(residuals.^2, 1, 'omitnan'))';
resRmseNoIC = sqrt(mean(residuals_no_ic.^2, 1, 'omitnan'))';

nearLower = false(results.n_params, 1);
nearUpper = false(results.n_params, 1);
distanceToLowerPct = NaN(results.n_params, 1);
distanceToUpperPct = NaN(results.n_params, 1);
if ~isempty(lb_params) && ~isempty(ub_params)
    lb = lb_params(:);
    ub = ub_params(:);
    if numel(lb) ~= results.n_params || numel(ub) ~= results.n_params
        error('diagnose_uq_quality:BoundsMismatch', ...
            'lb_params and ub_params must contain one value per parameter.');
    end
    span = ub - lb;
    validSpan = span > 0;
    distanceToLowerPct(validSpan) = 100 * (paramEst(validSpan) - lb(validSpan)) ./ span(validSpan);
    distanceToUpperPct(validSpan) = 100 * (ub(validSpan) - paramEst(validSpan)) ./ span(validSpan);
    nearLower = distanceToLowerPct <= 5;
    nearUpper = distanceToUpperPct <= 5;
end

method = "CUQDyn1_Plus";
if isfield(results, 'Cov_p_fim') && isfield(results, 'Cov_p_loo')
    method = "CUQDyn1_Plus_HybridCov";
end

summaryTable = table( ...
    method, results.nstates, results.n_params, numel(results.times), ...
    numel(results.observed_idx), cond(Cov_p), min(covEig), max(covEig), ...
    sum(covEig < -1e-10), sum(abs(covEig) <= 1e-12), ...
    sigma2_all, sigma2_no_ic, maxAbsCorr, ...
    fimRank, fimConditionNumber, fimWeakDirections, fimMaxWeakFraction, fimAnyUnreliableBands, ...
    'VariableNames', {'Method', 'NStates', 'NParams', 'NTimePoints', ...
    'NObservedStates', 'ConditionNumberCovP', 'MinCovEigenvalue', ...
    'MaxCovEigenvalue', 'NNegativeCovEigenvalues', 'NTinyCovEigenvalues', ...
    'Sigma2AllResiduals', 'Sigma2NoInitialCondition', 'MaxAbsParameterCorrelation', ...
    'FIMRank', 'FIMConditionNumber', 'FIMWeakDirections', ...
    'FIMMaxWeakFraction', 'FIMAnyUnreliableBands'});

paramTable = table( ...
    param_names, paramEst, paramStd, relParamStd, ...
    distanceToLowerPct, distanceToUpperPct, nearLower, nearUpper, ...
    'VariableNames', {'Parameter', 'Estimate', 'StdDev', 'RelativeStdDev', ...
    'DistanceToLowerPct', 'DistanceToUpperPct', 'NearLowerBound', 'NearUpperBound'});

residualTable = table(obsStateNames, results.observed_idx(:), resRmse, resRmseNoIC, ...
    'VariableNames', {'ObservedState', 'StateIndex', 'RMSEAllResiduals', 'RMSENoInitialCondition'});

eigTable = table((1:numel(covEig))', covEig, ...
    'VariableNames', {'EigenvalueIndex', 'CovPEigenvalue'});

corrTable = array2table(Corr_p, 'VariableNames', matlab.lang.makeValidName(param_names));
corrTable.Parameter = param_names;
corrTable = movevars(corrTable, 'Parameter', 'Before', 1);

diagnostics = struct();
diagnostics.summaryTable = summaryTable;
diagnostics.parameterTable = paramTable;
diagnostics.residualTable = residualTable;
diagnostics.eigenvalueTable = eigTable;
diagnostics.correlationTable = corrTable;

if isfield(results, 'Cov_p_fim') && isfield(results, 'Cov_p_loo')
    fimStd = sqrt(max(diag(results.Cov_p_fim), 0));
    looStd = sqrt(max(diag(results.Cov_p_loo), 0));
    hybStd = sqrt(max(diag(results.Cov_p), 0));
    diagnostics.hybridStdTable = table(param_names, fimStd, looStd, hybStd, ...
        'VariableNames', {'Parameter', 'FIMStdDev', 'LOOStdDev', 'HybridStdDev'});
end

excelFile = fullfile(resultDir, 'uq_diagnostics.xlsx');
writetable(summaryTable, excelFile, 'Sheet', 'Summary');
writetable(paramTable, excelFile, 'Sheet', 'Parameters');
writetable(residualTable, excelFile, 'Sheet', 'Residuals');
writetable(eigTable, excelFile, 'Sheet', 'CovEigenvalues');
writetable(corrTable, excelFile, 'Sheet', 'ParamCorrelation');
if isfield(diagnostics, 'hybridStdTable')
    writetable(diagnostics.hybridStdTable, excelFile, 'Sheet', 'HybridStdDevs');
end
if isfield(results, 'diagnostics') && isfield(results.diagnostics, 'fim_reliability')
    rel = results.diagnostics.fim_reliability;
    reliabilityTable = table((1:results.nstates)', state_names, ...
        rel.maxWeakFractionByState(:), rel.meanWeakFractionByState(:), ...
        rel.bandUnreliableByState(:), ...
        'VariableNames', {'StateIndex', 'StateName', 'MaxWeakFraction', ...
        'MeanWeakFraction', 'BandUnreliable'});
    diagnostics.fimReliabilityTable = reliabilityTable;
    writetable(reliabilityTable, excelFile, 'Sheet', 'FIMReliability');
end

save(fullfile(resultDir, 'uq_diagnostics.mat'), 'diagnostics');

fprintf('\n=== UQ quality diagnostics ===\n');
disp(summaryTable);
fprintf('Parameter diagnostics\n');
disp(paramTable);
fprintf('Observed-state residual diagnostics\n');
disp(residualTable);
fprintf('UQ diagnostics saved to %s\n', excelFile);

end

function Corr = safe_corr_from_cov(Cov)
    d = sqrt(max(diag(Cov), 0));
    denom = d * d';
    Corr = Cov ./ denom;
    Corr(denom == 0) = NaN;
    Corr(1:size(Corr,1)+1:end) = 1;
    Corr = max(min(Corr, 1), -1);
end
