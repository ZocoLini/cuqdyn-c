%% save_results_to_excel - Function to save results to Excel
% Saves problem characteristics and main results to an Excel file.
% Inputs: results (struct), resultDir (string), true_parameters (vector),
% guess_params (vector), lb_params (vector), ub_params (vector),
% data_file_name (string)

function save_results_to_excel(results, resultDir, true_parameters, guess_params, lb_params, ub_params, data_file_name)

excelFile = fullfile(resultDir, 'results_summary.xlsx');

% Problem Config
configTable = table();
configTable.Property = {'nstates'; 'n_params'; 'true_parameters'; 'guess_params'; 'lb_params'; 'ub_params'; 'alp'; 'data_file_name'};
configTable.Value = {results.nstates; results.n_params; true_parameters; guess_params; lb_params; ub_params; results.alp; data_file_name};
writetable(configTable, excelFile, 'Sheet', 'Config');

% Times
writematrix(results.times, excelFile, 'Sheet', 'Times');

% All State Data
writematrix(results.all_state_data, excelFile, 'Sheet', 'AllStateData');

% Observed Data
writematrix(results.observed_data, excelFile, 'Sheet', 'ObservedData');

% Initial Values
writematrix(results.initial_values_all_states, excelFile, 'Sheet', 'InitialValues');

% Observed Indices
writematrix(results.observed_idx, excelFile, 'Sheet', 'ObservedIdx');

% Parameters Init
writematrix(results.parameters_init, excelFile, 'Sheet', 'ParametersInit');

% Media Tot
writematrix(results.media_tot, excelFile, 'Sheet', 'MediaTot');

% Resid LOO
writematrix(results.resid_loo, excelFile, 'Sheet', 'ResidLOO');

% UQ Lower
writematrix(results.UQ_lower, excelFile, 'Sheet', 'UQLower');

% UQ Upper
writematrix(results.UQ_upper, excelFile, 'Sheet', 'UQUpper');

% Cov P
writematrix(results.Cov_p, excelFile, 'Sheet', 'CovP');

% Std Y
writematrix(results.std_y, excelFile, 'Sheet', 'StdY');

% Media Matrix (one sheet per state)
for i = 1:results.nstates
    sheetName = sprintf('MediaMatrix_State%d', i);
    writematrix(squeeze(results.media_matrix(:,i,:)), excelFile, 'Sheet', sheetName);
end

fprintf('Results saved to %s\n', excelFile);

end
