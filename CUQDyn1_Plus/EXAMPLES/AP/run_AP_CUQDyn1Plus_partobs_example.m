%% run_AP_CUQDyn1Plus_partobs_example - Define AP problem and call CUQDyn1_Plus
% This script defines problem-specific variables and calls the modular CUQDyn1_Plus function.

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% --- Config ---
dynamics_handle = @prob_mod_dynamics_AP;
cost_handle = @prob_mod_cost_AP;
nstates = 5; 
n_params = 5;
true_parameters = [5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05];
guess_params = true_parameters*0.8;
lb_params = true_parameters*0.05;
ub_params = true_parameters*5.0;
alp = 0.05;

% --- Optimiser / integration defaults ---
opts = cuqdyn_default_options(n_params);
opts.uq.alp = alp;
opts.meigo.maxeval = n_params * 2000;
opts.meigo.iterprint = 1;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

% partially observed data set
dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
% data_file_name = 'AP_synthetic_data_10_partobs1_4.csv'; 
data_file_name = 'AP_measurementData_1_4.csv';

% --- Load data
[times, all_state_data, initial_values_all_states, observed_data, observed_idx] = loadStateData(dataDir, data_file_name, nstates);

% --- Generate timestamped results directory ---
nowTime = datetime('now');
timestamp = string(nowTime, 'yyyy-MM-dd_HH-mm-ss');
resultDir = "Results_AP_partobs1_4_" + timestamp;
if ~exist(resultDir, 'dir'), mkdir(resultDir); end

% --- Call the function ---
CUQDyn_results = CUQDyn1_Plus(cost_handle,dynamics_handle, nstates, n_params, guess_params, lb_params, ub_params, alp,times, all_state_data, initial_values_all_states, observed_data, observed_idx, resultDir, meigo_opts);

% --- Plot the results ans save the figure ---
plot_hybrid_uq(CUQDyn_results, resultDir);

% --- Save results in Excel format ---
% save_results_to_excel(CUQDyn_results, resultDir, true_parameters, guess_params, lb_params, ub_params, data_file_name);
save_results_to_excel_detailed(CUQDyn_results, resultDir, true_parameters, guess_params, lb_params, ub_params, data_file_name);

% --- Parameter recovery summary ---
print_param_recovery(CUQDyn_results, true_parameters, ...
                     {'k1','k2','k3','k4','k5'}, alp);

% --- Trajectory prediction error summary --
save_trajectory_nrmse_tables(CUQDyn_results, resultDir);
