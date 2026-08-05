function save_results_to_excel_detailed(results, resultDir, true_parameters, guess_params, lb_params, ub_params, data_file_name)
%SAVE_RESULTS_TO_EXCEL_DETAILED Export CUQDyn results to an annotated workbook.
%
% save_results_to_excel_detailed(results, resultDir, true_parameters,
% guess_params, lb_params, ub_params, data_file_name) writes
% results_detailed.xlsx in resultDir. The workbook records run metadata,
% input data, fitted trajectory, LOO ensemble objects, UQ bands, covariance
% matrices, and compact sheet descriptions.
%
% This is the maintained detailed exporter used by the examples. The older
% save_results_to_excel.m helper writes a smaller summary workbook.

excelFile = fullfile(resultDir, 'results_detailed.xlsx');

% --- Generate descriptive names ---
state_names = arrayfun(@(x) sprintf('State%d', x), 1:results.nstates, 'UniformOutput', false);
param_names = arrayfun(@(x) sprintf('Param%d', x), 1:results.n_params, 'UniformOutput', false);
obs_state_names = state_names(results.observed_idx);
res_names = arrayfun(@(x) sprintf('Resid_State%d', x), results.observed_idx, 'UniformOutput', false);
lower_names = arrayfun(@(x) sprintf('Lower_State%d', x), 1:results.nstates, 'UniformOutput', false);
upper_names = arrayfun(@(x) sprintf('Upper_State%d', x), 1:results.nstates, 'UniformOutput', false);
std_names = arrayfun(@(x) sprintf('Std_State%d', x), 1:results.nstates, 'UniformOutput', false);
m = size(results.times, 1);
ens_names = arrayfun(@(x) sprintf('Ensemble%d', x), 1:(m-1), 'UniformOutput', false);

% --- Descriptions Sheet (first for visibility) ---
sheet_names = {'Config', 'Times', 'AllStateData', 'ObservedData', 'InitialValues', ...
               'ObservedIdx', 'ParametersInit', 'MediaTot', 'ResidLOO', ...
               'UQLower', 'UQUpper', 'CovP', 'StdY'};
descriptions = {'Problem configuration parameters and values', ...
                'Time points for the simulations and data', ...
                'All state data (including NaNs for unobserved states)', ...
                'Observed state data only', ...
                'Initial values for all states at t=0', ...
                'Indices of the observed states', ...
                'Estimated initial parameters from the full fit', ...
                'Median predictions (media_tot) for all states', ...
                'Leave-one-out (LOO) residuals for observed states', ...
                'Uncertainty quantification lower bounds for all states', ...
                'Uncertainty quantification upper bounds for all states', ...
                'Parameter covariance matrix (Cov_p)', ...
                'Standard deviations of predictions (std_y) for all states'};
for i = 1:results.nstates
    sheet_names{end+1} = sprintf('MediaMatrix_State%d', i);
    descriptions{end+1} = sprintf('LOO ensemble predictions for state %d (times in first column, ensembles in subsequent columns)', i);
end
descTable = table(sheet_names', descriptions', 'VariableNames', {'Sheet', 'Description'});
writetable(descTable, excelFile, 'Sheet', 'Descriptions');

% --- Problem Config ---
configTable = table();
configTable.Property = {'nstates'; 'n_params'; 'true_parameters'; 'guess_params'; 'lb_params'; 'ub_params'; 'alp'; 'data_file_name'};
configTable.Value = {results.nstates; results.n_params; true_parameters; guess_params; lb_params; ub_params; results.alp; data_file_name};
writetable(configTable, excelFile, 'Sheet', 'Config');

% --- Times ---
T = array2table(results.times, 'VariableNames', {'Time'});
writetable(T, excelFile, 'Sheet', 'Times');

% --- All State Data ---
data_with_time = [results.times, results.all_state_data];
T = array2table(data_with_time, 'VariableNames', [{'Time'}, state_names]);
writetable(T, excelFile, 'Sheet', 'AllStateData');

% --- Observed Data ---
obsdata_with_time = [results.times, results.observed_data];
T = array2table(obsdata_with_time, 'VariableNames', [{'Time'}, obs_state_names]);
writetable(T, excelFile, 'Sheet', 'ObservedData');

% --- Initial Values ---
T = array2table(results.initial_values_all_states, 'VariableNames', state_names);
writetable(T, excelFile, 'Sheet', 'InitialValues');

% --- Observed Indices ---
T = array2table(results.observed_idx', 'VariableNames', {'ObservedIndex'});
writetable(T, excelFile, 'Sheet', 'ObservedIdx');

% --- Parameters Init ---
T = array2table(results.parameters_init, 'VariableNames', param_names);
writetable(T, excelFile, 'Sheet', 'ParametersInit');

% --- Media Tot ---
mediatot_with_time = [results.times, results.media_tot];
T = array2table(mediatot_with_time, 'VariableNames', [{'Time'}, state_names]);
writetable(T, excelFile, 'Sheet', 'MediaTot');

% --- Resid LOO ---
T = array2table(results.resid_loo, 'VariableNames', res_names);
writetable(T, excelFile, 'Sheet', 'ResidLOO');

% --- UQ Lower ---
T = array2table(results.UQ_lower, 'VariableNames', lower_names);
writetable(T, excelFile, 'Sheet', 'UQLower');

% --- UQ Upper ---
T = array2table(results.UQ_upper, 'VariableNames', upper_names);
writetable(T, excelFile, 'Sheet', 'UQUpper');

% --- Cov P ---
T = array2table(results.Cov_p, 'VariableNames', param_names, 'RowNames', param_names);
writetable(T, excelFile, 'Sheet', 'CovP', 'WriteRowNames', true);

% --- Std Y ---
T = array2table(results.std_y, 'VariableNames', std_names);
writetable(T, excelFile, 'Sheet', 'StdY');

% --- Media Matrix (one sheet per state) ---
for i = 1:results.nstates
    sheetName = sprintf('MediaMatrix_State%d', i);
    data = squeeze(results.media_matrix(:,i,:));
    T = array2table([results.times, data], 'VariableNames', [{'Time'}, ens_names]);
    writetable(T, excelFile, 'Sheet', sheetName);
end

fprintf('Results saved to %s\n', excelFile);

end
