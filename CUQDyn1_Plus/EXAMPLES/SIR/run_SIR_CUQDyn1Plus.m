%% run_SIR_CUQDyn1Plus.m
% --------------------------------------------------------
% BENCHMARK: NON-LINEAR SIR MODEL  —  CUQDyn1_Plus
% --------------------------------------------------------
% Observed:   State 2 (Infected)
% Unobserved: State 1 (Susceptible), State 3 (Recovered)
%
% Adapted from run_SIR_Example.m to use the current CUQDyn1_Plus
% toolbox interface:
%   - data loaded from a pre-existing CSV using loadStateData
%   - timestamped result directory
%   - plot_hybrid_uq and save_results_to_excel_detailed for output
%

clear; close all; clc;
addpath(genpath('../../'));

% ====================================================================
% 1. PROBLEM CONFIGURATION
% ====================================================================
fprintf('--- 1. Problem configuration ---\n');

dynamics_handle = @prob_mod_dynamics_SIR;
cost_handle     = @prob_mod_cost_SIR;

nstates  = 3;
n_params = 2;
param_names = {'beta','gamma'};

% True parameters
%   beta  = 0.002  (interaction / transmission rate)
%   gamma = 0.5    (recovery rate, i.e. 1/gamma = 2 days)
true_params = [0.002, 0.5];

% Initial conditions and time points are read from data/sir_data.csv.

% Optimisation bounds and initial guess
guess_params = [0.001, 0.2];
lb_params    = [0.0001, 0.01];
ub_params    = [0.01,   2.0];
alp          = 0.05;   % nominal 1-2*alp = 90% two-sided coverage

% Optimiser / integration defaults
opts = cuqdyn_default_options(n_params);
opts.uq.alp = alp;
opts.ode.RelTol = 1e-8;
opts.ode.AbsTol = 1e-8;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

% ====================================================================
% 2. LOAD SYNTHETIC DATA
% ====================================================================
fprintf('--- 2. Loading synthetic epidemic data from CSV ---\n');

dataDir = fullfile(fileparts(mfilename('fullpath')), 'data');
data_file_name = 'sir_data.csv';
[times, all_state_data, initial_values_all_states, observed_data, observed_idx] = ...
    loadStateData(dataDir, data_file_name, nstates);

options_ode = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t,y) dynamics_handle(t,y,true_params), ...
                     times, initial_values_all_states, options_ode);

% Add proportional Gaussian noise to Infected (State 2) only.
% sigma is computed as noise_pct% of the mean true trajectory value,
% giving constant relative SNR across the epidemic curve.
% Noise is applied from t_2 onward; t=0 (initial condition) is kept exact.
noise_pct   = 10;
sigma_noise = (noise_pct/100) * mean(Y_true(2:end, 2));
fprintf('   Noise sigma (proportional, %.0f%% of mean I): %.4f\n', ...
        noise_pct, sigma_noise);
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = sigma_noise;
opts.cost.sigma_is_known = true;
meigo_opts.cost_opts = opts.cost;

% ====================================================================
% 3. RESULTS DIRECTORY
% ====================================================================
nowTime   = datetime('now');
timestamp = string(nowTime,'yyyy-MM-dd_HH-mm-ss');
resultDir = "Results_SIR_CUQDyn1Plus_" + timestamp;
mkdir(resultDir);

% ====================================================================
% 4. RUN CUQDyn1_Plus
% ====================================================================
fprintf('--- 3. Running CUQDyn1_Plus ---\n');

results = CUQDyn1_Plus( ...
    cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, initial_values_all_states, ...
    observed_data, observed_idx, resultDir, meigo_opts);

% Standard toolbox outputs
plot_hybrid_uq(results, resultDir);
save_results_to_excel_detailed(results, resultDir, true_params, ...
                                guess_params, lb_params, ub_params, data_file_name);

% Parameter recovery summary
print_param_recovery(results, true_params, param_names, alp);


% --- Trajectory prediction error summary --
save_trajectory_nrmse_tables(results, resultDir);


% ====================================================================
% 5. PLOT: toolbox results against true trajectory
% ====================================================================
fprintf('--- 4. Plotting ---\n');

state_labels = {'Susceptible (hidden)','Infected (observed)','Recovered (hidden)'};
fill_colors  = {[0.85 0.2 0.2], [0.2 0.3 0.85], [0.85 0.2 0.2]};

fig = figure('Color','w','Position',[50 50 1300 420]);

for st = 1:nstates
    subplot(1, nstates, st); hold on; grid on;
    title(sprintf('State %d: %s', st, state_labels{st}), ...
          'FontSize',11,'FontWeight','bold');

    % CUQDyn1_Plus band
    lo_tb = max(0, results.UQ_lower(:,st));
    hi_tb =        results.UQ_upper(:,st);
    fill([times; flipud(times)], [lo_tb; flipud(hi_tb)], ...
         fill_colors{st}, 'FaceAlpha',0.30,'EdgeColor','none', ...
         'DisplayName','CUQDyn1\_Plus 90% CI');

    % Best-fit trajectory
    plot(times, results.media_tot(:,st), 'b-','LineWidth',1.5,'DisplayName','Best fit');

    % True trajectory
    plot(times, Y_true(:,st), 'g-','LineWidth',2,'DisplayName','True');

    % Data points (observed state only)
    if st == observed_idx
        plot(times, observed_data,'ko','MarkerSize',4,'DisplayName','Data');
    end

    xlabel('Time (days)','FontSize',11);
    ylabel('Population','FontSize',11);
    if st == 1
        legend('Location','southwest','FontSize',9);
    end
end
sgtitle('SIR model — CUQDyn1\_Plus hybrid UQ','FontSize',13,'FontWeight','bold');

savefig_png(fig, fullfile(resultDir,'sir_cuqdyn1plus_results'));

fprintf('\nAll results saved to: %s\n', resultDir);
