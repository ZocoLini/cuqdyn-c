%% run_NFKB_example - Script to define NFKB problem and call CUQDyn1_Plus
% This script defines problem-specific variables and calls the modular CUQDyn1_Plus function.

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% --- Config ---
dynamics_handle = @prob_mod_dynamics_NFKB;
cost_handle = @prob_mod_cost_NFKB;
nstates = 15; 
n_params = 29;
true_parameters = [0.5 0.2 0.1 1 0.1 5e-7 0.0001 0.0004 0.5 ...
                 0.0001 0.00002 5e-7 0.0001 0.0004 0.5 0.0003 ...
                 0.0025 0.1 0.0015 0.000025 0.000125 5 ...
                 0.0025 0.01 0.001 0.0005 5e-7 0.0001 0.0004]; % Nominal parameters
% Wide positive bounds around the nominal parameters.
guess_params = true_parameters*0.8;
lb_params = true_parameters*0.1;
ub_params = true_parameters*4.0;
alp = 0.05;

% --- Optimiser / integration defaults ---
opts = cuqdyn_default_options(n_params);
opts.uq.alp = alp;
opts.meigo.maxeval = 2e4;
opts.meigo.local.solver = 'lsqnonlin';
opts.meigo.iterprint = 0;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

% partially observed data set
dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
data_file_name = 'NFKB_synthetic_data_5n_36st_partobs10.csv'; % 5 % noise, 36 sampling times, 10 observed states
% other data files included:
% 'NFKB_synthetic_data_5n_18st_partobs7.csv';% 'NFKB_synthetic_data_5n_18st_fullobs.csv';%'NFKB_synthetic_data_5_fullobs.csv';

% --- Load data
[times, all_state_data, initial_values_all_states, observed_data, observed_idx] = loadStateData(dataDir, data_file_name, nstates);

noise_pct = 5;
[ode_options, ~] = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t,y) dynamics_handle(t,y,true_parameters), ...
    times, initial_values_all_states, ode_options);
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, noise_pct);
opts.cost.sigma_is_known = true;
meigo_opts.cost_opts = opts.cost;

% --- Generate timestamped results directory ---
nowTime = datetime('now');
timestamp = string(nowTime, 'yyyy-MM-dd_HH-mm-ss');
resultDir = "Results_NFKB_" + timestamp;
if ~exist(resultDir, 'dir'), mkdir(resultDir); end

% --- Call the function ---
CUQDyn_results = CUQDyn1_Plus(cost_handle, dynamics_handle, nstates, n_params, guess_params, lb_params, ub_params, alp, times, all_state_data, initial_values_all_states, observed_data, observed_idx, resultDir, meigo_opts);

% --- Plot the results ans save the figure ---
plot_hybrid_uq(CUQDyn_results, resultDir);

% --- Parameter recovery summary ---
param_names = {'p1','p2','p3','p4','p5','p6','p7','p8','p9','p10', ...
               'p11','p12','p13','p14','p15','p16','p17','p18','p19','p20', ...
               'p21','p22','p23','p24','p25','p26','p27','p28','p29'};
print_param_recovery(CUQDyn_results, true_parameters, param_names, alp);

% --- Save results in Excel format ---
% save_results_to_excel(CUQDyn_results, resultDir, true_parameters, guess_params, lb_params, ub_params, data_file_name);
save_results_to_excel_detailed(CUQDyn_results, resultDir, true_parameters, guess_params, lb_params, ub_params, data_file_name);
