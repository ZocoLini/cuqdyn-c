function [summaryTable, residualTable] = save_trajectory_nrmse_tables(results, resultDir, state_names, fileBase)
%SAVE_TRAJECTORY_NRMSE_TABLES  Summarize prediction errors against data.
%
%   [summaryTable, residualTable] = save_trajectory_nrmse_tables(results, resultDir)
%   compares results.media_tot against finite entries in results.all_state_data,
%   writes an Excel workbook, and prints a compact NRMSE summary.
%   Optional state_names and fileBase arguments customize state labels and the
%   output workbook basename.
%
%   NRMSE is RMSE normalized by the finite data range for each state:
%       NRMSE = sqrt(mean((prediction - data).^2)) / (max(data) - min(data))
%   If fewer than two finite data values exist, or the data range is zero, NRMSE
%   is reported as NaN.
%
%   The summary also reports MAE, empirical coverage of finite data by
%   results.UQ_lower/results.UQ_upper, and mean interval width normalized by
%   the state data range. The workbook splits these metrics into compact
%   sheets for readability.
%
% Interpretation note:
%   For observed states, coverage is against observed data. For hidden states,
%   coverage is only meaningful when finite reference trajectories are present
%   in results.all_state_data.

if nargin < 3 || isempty(state_names)
    state_names = arrayfun(@(j) sprintf('State%d', j), 1:results.nstates, 'UniformOutput', false);
end
if nargin < 4 || isempty(fileBase)
    fileBase = 'trajectory_nrmse_tables';
end

resultDir = char(resultDir);
if ~exist(resultDir, 'dir')
    mkdir(resultDir);
end

times          = results.times(:);
data           = results.all_state_data;
pred           = results.media_tot;
observed_idx   = results.observed_idx(:)';
nstates        = results.nstates;

if size(data, 1) ~= numel(times) || size(pred, 1) ~= numel(times)
    error('save_trajectory_nrmse_tables:SizeMismatch', ...
        'results.times, results.all_state_data, and results.media_tot must have matching row counts.');
end
if size(data, 2) ~= nstates || size(pred, 2) ~= nstates
    error('save_trajectory_nrmse_tables:StateMismatch', ...
        'results.all_state_data and results.media_tot must each have results.nstates columns.');
end
if numel(state_names) ~= nstates
    error('save_trajectory_nrmse_tables:StateNameMismatch', ...
        'state_names must contain one name per state.');
end

stateIndex      = (1:nstates)';
stateName       = state_names(:);
isObserved      = ismember(stateIndex, observed_idx);
nDataPoints     = zeros(nstates, 1);
rmse            = NaN(nstates, 1);
mae             = NaN(nstates, 1);
dataRange       = NaN(nstates, 1);
nrmse           = NaN(nstates, 1);
nrmsePercent    = NaN(nstates, 1);
coveragePercent = NaN(nstates, 1);
meanIntervalWidth = NaN(nstates, 1);
normalizedMeanIntervalWidth = NaN(nstates, 1);

hasUQ = isfield(results, 'UQ_lower') && isfield(results, 'UQ_upper') && ...
    isequal(size(results.UQ_lower), size(pred)) && isequal(size(results.UQ_upper), size(pred));

resTime         = [];
resStateIndex   = [];
resStateName    = {};
resIsObserved   = [];
resData         = [];
resPrediction   = [];
resResidual     = [];
resAbsError     = [];
resSquaredError = [];

for j = 1:nstates
    data_j = data(:, j);
    pred_j = pred(:, j);
    finiteMask = isfinite(data_j) & isfinite(pred_j);

    nDataPoints(j) = sum(finiteMask);
    if nDataPoints(j) > 0
        residuals = pred_j(finiteMask) - data_j(finiteMask);
        rmse(j) = sqrt(mean(residuals.^2));
        mae(j) = mean(abs(residuals));
        dataRange(j) = max(data_j(finiteMask)) - min(data_j(finiteMask));
        if nDataPoints(j) >= 2 && dataRange(j) > 0
            nrmse(j) = rmse(j) / dataRange(j);
            nrmsePercent(j) = 100 * nrmse(j);
        end

        if hasUQ
            lower_j = results.UQ_lower(:, j);
            upper_j = results.UQ_upper(:, j);
            uqMask = finiteMask & isfinite(lower_j) & isfinite(upper_j);
            if any(uqMask)
                inside = data_j(uqMask) >= lower_j(uqMask) & data_j(uqMask) <= upper_j(uqMask);
                widths = upper_j(uqMask) - lower_j(uqMask);
                coveragePercent(j) = 100 * mean(inside);
                meanIntervalWidth(j) = mean(widths);
                if dataRange(j) > 0
                    normalizedMeanIntervalWidth(j) = meanIntervalWidth(j) / dataRange(j);
                end
            end
        end

        n = nDataPoints(j);
        resTime         = [resTime; times(finiteMask)]; %#ok<AGROW>
        resStateIndex   = [resStateIndex; repmat(j, n, 1)]; %#ok<AGROW>
        resStateName    = [resStateName; repmat(state_names(j), n, 1)]; %#ok<AGROW>
        resIsObserved   = [resIsObserved; repmat(isObserved(j), n, 1)]; %#ok<AGROW>
        resData         = [resData; data_j(finiteMask)]; %#ok<AGROW>
        resPrediction   = [resPrediction; pred_j(finiteMask)]; %#ok<AGROW>
        resResidual     = [resResidual; residuals]; %#ok<AGROW>
        resAbsError     = [resAbsError; abs(residuals)]; %#ok<AGROW>
        resSquaredError = [resSquaredError; residuals.^2]; %#ok<AGROW>
    end
end

summaryTable = table(stateIndex, stateName, isObserved, nDataPoints, rmse, ...
    mae, dataRange, nrmse, nrmsePercent, coveragePercent, ...
    meanIntervalWidth, normalizedMeanIntervalWidth, ...
    'VariableNames', {'StateIndex', 'StateName', 'IsObserved', 'NDataPoints', ...
    'RMSE', 'MAE', 'DataRange', 'NRMSE', 'NRMSEPercent', 'CoveragePercent', ...
    'MeanIntervalWidth', 'NormalizedMeanIntervalWidth'});

residualTable = table(resTime, resStateIndex, resStateName, resIsObserved, ...
    resData, resPrediction, resResidual, resAbsError, resSquaredError, ...
    'VariableNames', {'Time', 'StateIndex', 'StateName', 'IsObserved', ...
    'Data', 'Prediction', 'Residual', 'AbsError', 'SquaredError'});

dataSummaryTable = summaryTable(:, {'StateIndex', 'StateName', 'IsObserved', 'NDataPoints'});
errorSummaryTable = summaryTable(:, {'StateName', 'RMSE', 'MAE', 'DataRange', 'NRMSEPercent'});
uqSummaryTable = summaryTable(:, {'StateName', 'CoveragePercent', ...
    'MeanIntervalWidth', 'NormalizedMeanIntervalWidth'});

excelFile = fullfile(resultDir, [char(fileBase) '.xlsx']);
writetable(dataSummaryTable, excelFile, 'Sheet', 'DataSummary');
writetable(errorSummaryTable, excelFile, 'Sheet', 'ErrorSummary');
writetable(uqSummaryTable, excelFile, 'Sheet', 'UQSummary');
writetable(residualTable, excelFile, 'Sheet', 'PointwiseResiduals');

fprintf('\n=== Trajectory prediction error summary ===\n');
fprintf('\nData availability\n');
disp(dataSummaryTable);
fprintf('Trajectory errors\n');
disp(errorSummaryTable);
fprintf('Uncertainty band diagnostics\n');
disp(uqSummaryTable);
fprintf('Trajectory NRMSE tables saved to %s\n', excelFile);

end
