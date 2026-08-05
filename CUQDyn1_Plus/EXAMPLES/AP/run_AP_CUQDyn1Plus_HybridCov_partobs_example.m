%% run_AP_CUQDyn1Plus_HybridCov_partobs_example.m
% Solves the alpha-pinene isomerization (AP) partial obs example using
% the Hybrid FIM-scale / LOO-correlation covariance method.
%
% Identical to run_AP_CUQDyn1Plus_partobs_example.m except:
%   - CUQDyn1_Plus        replaced by CUQDyn1_Plus_HybridCov
%   - resultDir name      updated accordingly
%
% States 1-4 observed; state 5 unobserved after t=0.

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% --- Config ---
dynamics_handle = @prob_mod_dynamics_AP;
cost_handle     = @prob_mod_cost_AP;
nstates         = 5;
n_params        = 5;
true_parameters = [5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05];
guess_params    = true_parameters * 0.8;
lb_params       = true_parameters * 0.05;
ub_params       = true_parameters * 5.0;
alp             = 0.05;

% --- Optimiser / integration defaults ---
opts = cuqdyn_default_options(n_params);
opts.uq.alp = alp;
opts.meigo.maxeval = n_params * 4000;
opts.meigo.iterprint = 0;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

% --- Data ---
dataDir        = fullfile(fileparts(mfilename('fullpath')), 'data');
data_file_name = 'AP_measurementData_1_4.csv';

% --- Load data ---
[times, all_state_data, initial_values_all_states, observed_data, observed_idx] = ...
    loadStateData(dataDir, data_file_name, nstates);

% --- Timestamped results directory ---
nowTime   = datetime('now');
timestamp = string(nowTime, 'yyyy-MM-dd_HH-mm-ss');
resultDir = "Results_AP_HybridCov_partobs1_4_" + timestamp;
if ~exist(resultDir, 'dir'), mkdir(resultDir); end

% --- Run hybrid method ---
CUQDyn_results = CUQDyn1_Plus_HybridCov( ...
    cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, initial_values_all_states, ...
    observed_data, observed_idx, resultDir, meigo_opts);

% --- Plot ---
plot_hybrid_uq(CUQDyn_results, resultDir);

% --- Save to Excel ---
save_results_to_excel_detailed(CUQDyn_results, resultDir, true_parameters, ...
    guess_params, lb_params, ub_params, data_file_name);

% --- Parameter recovery summary ---
print_param_recovery(CUQDyn_results, true_parameters, ...
                     {'k1','k2','k3','k4','k5'}, alp);

% --- Trajectory prediction error summary --
save_trajectory_nrmse_tables(CUQDyn_results, resultDir);
