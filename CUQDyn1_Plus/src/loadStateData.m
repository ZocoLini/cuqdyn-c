function [times, all_state_data, initial_values_all_states, observed_data, observed_idx] = loadStateData(dataDir, data_file_name, nstates)
%LOADSTATEDATA Load CUQDyn CSV data and infer observed states.
%
% The expected CSV layout is:
%   column 1     time
%   columns 2:N all model states
%   row 1        finite initial values for every state
%   rows 2:end   finite values for observed states and NaN for hidden states
%
% A state is considered observed when its post-initial column has no NaN
% values. The initial row is always used as the full ODE initial condition.
%
% Inputs:
%   dataDir         folder containing the CSV file.
%   data_file_name  CSV filename.
%   nstates         expected number of model states.
%
% Outputs:
%   times                      time vector.
%   all_state_data             data matrix for all states, including NaNs.
%   initial_values_all_states  row vector of initial values at t=0.
%   observed_data              data matrix restricted to observed states.
%   observed_idx               indices of observed states.

    % --- Load Data ---
    fprintf('Loading: %s\n', data_file_name);
    
    % Read the matrix from the specified file path
    data_matrix = readmatrix(fullfile(dataDir, data_file_name));
    
    % Extract time points (column 1) and state data (remaining columns)
    times = data_matrix(:,1);
    all_state_data = data_matrix(:,2:end);
    
    % Determine actual number of states and time steps
    nstate = size(all_state_data, 2);
    m = size(data_matrix,1); % 
    
    % Check for state count mismatch
    if nstate ~= nstates
        error('State mismatch. Expected %d states but found %d.', nstates, nstate);
    end
    
    % --- Determine Observed States ---
    % Check for NaNs starting from the second row (t > 0). 
    % The 'any(..., 1)' checks if any element in a column is a NaN.
    has_nans = any(isnan(all_state_data(2:end,:)), 1);
    
    % A state is 'observed' if it does NOT have NaNs after t=0
    is_observed = ~has_nans;
    
    % Get the column indices of the observed states
    observed_idx = find(is_observed);
    
    % Extract data only for the observed states
    observed_data = all_state_data(:, observed_idx);
    
    % --- Check Initial Values ---
    initial_values_all_states = all_state_data(1,:);
    
    % Check for NaNs in the initial time point (t=0)
    if any(isnan(initial_values_all_states))
        error('NaNs found in initial values (t=0) of the state data.');
    end
    
    fprintf('Observed states (indices): %s\n', mat2str(observed_idx));
end
