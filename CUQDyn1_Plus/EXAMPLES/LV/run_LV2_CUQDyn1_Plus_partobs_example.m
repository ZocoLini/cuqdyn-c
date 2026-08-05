%% run_lv_example - Script to define LV problem and call CUQDyn1_Plus
% This script defines problem-specific variables and calls the modular CUQDyn1_Plus function.

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% --- Config ---
dynamics_handle = @prob_mod_dynamics_LV;
cost_handle = @prob_mod_cost_LV;
nstates = 2; 
n_params = 4;
true_parameters = [0.5,0.02,0.02,0.5];
guess_params = true_parameters*0.8;
lb_params = true_parameters*0.2;
ub_params = true_parameters*2.0;
% alp = 0.05; % 90% Confidence / Credible Interval
alp = 0.025; % 95% Confidence / Credible Interval

% --- Optimiser / integration defaults ---
opts = cuqdyn_default_options(n_params);
opts.uq.alp = alp;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

% partially observed data set
dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
data_file_name = 'lv2_synthetic_data_noi10_partobs_1.csv';

% --- Load data
[times, all_state_data, initial_values_all_states, observed_data, observed_idx] = loadStateData(dataDir, data_file_name, nstates);

% Synthetic data generator used additive Gaussian noise with sigma equal to
% noise_pct/100 times the mean true trajectory for each observed state.
noise_pct = 10;
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
resultDir = "Results_LV2_CUQDyn1_Plus_" + timestamp;
if ~exist(resultDir, 'dir'), mkdir(resultDir); end

% --- Call the function ---
CUQDyn_results = CUQDyn1_Plus(cost_handle,dynamics_handle, nstates, n_params, guess_params, lb_params, ub_params, alp,times, all_state_data, initial_values_all_states, observed_data, observed_idx, resultDir, meigo_opts);

% --- Plot the results ans save the figure ---
plot_hybrid_uq(CUQDyn_results, resultDir);

% --- Save results in Excel format ---
% save_results_to_excel(CUQDyn_results, resultDir, true_parameters, guess_params, lb_params, ub_params, data_file_name);
save_results_to_excel_detailed(CUQDyn_results, resultDir, true_parameters, guess_params, lb_params, ub_params, data_file_name);

% save workspace
save(fullfile(resultDir, 'CUQDyn1_Plus_workspace.mat'));

% --- Parameter recovery summary ---
print_param_recovery(CUQDyn_results, true_parameters, ...
                     {'alpha','beta','delta','gamma'}, alp);

% --- Trajectory prediction error summary ---
save_trajectory_nrmse_tables(CUQDyn_results, resultDir, {'Prey', 'Predator'});

% --- Optional bootstrap trajectory UQ ---
% Start with a small bootstrap run to verify the workflow. For production
% use, increase n_boot (e.g. 100) and maxeval (e.g. 3000).
boot_opts = struct();
boot_opts.n_boot = 10;
boot_opts.alp = alp;
boot_opts.meigo_opts = meigo_opts;
boot_opts.meigo_opts.maxeval = n_params * 125;
boot_opts.meigo_opts.iterprint = 0;

boot = bootstrap_trajectory_uq( ...
    CUQDyn_results, dynamics_handle, cost_handle, ...
    lb_params, ub_params, resultDir, boot_opts);
