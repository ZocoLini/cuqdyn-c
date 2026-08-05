%% run_LV2_CUQDyn1_Plus_HybridCov_partobs_example.m
%
% Lotka-Volterra partial obs example using CUQDyn1_Plus_HybridCov.
% Only prey (state 1) is observed; predator (state 2) is unobserved.
%
% The hybrid method uses:
%   - Conformal (jackknife+) intervals for the observed state
%   - Delta-method intervals for the unobserved state with
%       Cov_p = D_FIM * R_LOO * D_FIM
%     (FIM marginal variances, LOO correlation structure)
%
% Sections 1-6 are identical to the original LV run script.
% Section 7 adds hybrid-specific diagnostics comparing all three
% covariance estimates: FIM, LOO, and hybrid.
%

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% ====================================================================
% 1. PROBLEM DEFINITION
% ====================================================================
dynamics_handle    = @prob_mod_dynamics_LV;
cost_handle        = @prob_mod_cost_LV;
nstates            = 2;
n_params           = 4;
param_names        = {'alpha','beta','delta','gamma'};
true_parameters    = [0.5, 0.02, 0.02, 0.5];
initial_conditions = [10, 5];

lb_params    = true_parameters * 0.2;
ub_params    = true_parameters * 2.0;
guess_params = true_parameters * 0.8;
alp          = 0.025;

% --- Optimiser / integration defaults ---
opts = cuqdyn_default_options(n_params);
opts.uq.alp = alp;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

% ====================================================================
% 2. LOAD / GENERATE DATA
% ====================================================================
% Same pre-existing dataset used by run_LV2_CUQDyn1_Plus_partobs_example.m and lv_pymc.py.
dataDir  = fullfile(fileparts(mfilename('fullpath')), 'data');
dataFile = 'lv2_synthetic_data_noi10_partobs_1.csv';

[times, all_state_data, ic, observed_data, observed_idx] = ...
    loadStateData(dataDir, dataFile, nstates);

noise_pct = 10;
[ode_options, ~] = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t,y) dynamics_handle(t,y,true_parameters), ...
    times, ic, ode_options);
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, noise_pct);
opts.cost.sigma_is_known = true;
meigo_opts.cost_opts = opts.cost;

% ====================================================================
% 3. RUN CUQDyn1_Plus_HybridCov
% ====================================================================
nowTime   = datetime('now');
timestamp = string(nowTime,'yyyy-MM-dd_HH-mm-ss');
resultDir = "Results_LV2_HybridCov_" + timestamp;
mkdir(resultDir);

results = CUQDyn1_Plus_HybridCov( ...
    cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, ic, observed_data, observed_idx, resultDir, meigo_opts);

% ====================================================================
% 4. STANDARD UQ PLOT  (uses the shared plotting function)
% ====================================================================
plot_hybrid_uq(results, resultDir);

% ====================================================================
% 5. SAVE RESULTS TO EXCEL
% ====================================================================
save_results_to_excel_detailed(results, resultDir, true_parameters, ...
                                guess_params, lb_params, ub_params, dataFile);

% ====================================================================
% 6. PARAMETER RECOVERY and TRAJECTORY ERROR SUMMARY
% ====================================================================
print_param_recovery(results, true_parameters, param_names, 0.025);

% --- Trajectory prediction error summary --
save_trajectory_nrmse_tables(results, resultDir);

% ====================================================================
% 7. HYBRID-SPECIFIC DIAGNOSTICS
% ====================================================================

% --- Fig A: Three-way covariance comparison ---
% For each parameter, compare the marginal std dev from FIM, LOO, hybrid.
fig_a = figure('Color','w','Position',[100 100 900 380]);
hold on; grid on;
x  = 1:n_params;
bw = 0.25;
b1 = bar(x - bw, results.D_fim,            bw, 'FaceColor','r','FaceAlpha',0.7,'DisplayName','FIM std dev');
b2 = bar(x,      sqrt(diag(results.Cov_p_loo)), bw, 'FaceColor','b','FaceAlpha',0.7,'DisplayName','LOO std dev');
b3 = bar(x + bw, sqrt(diag(results.Cov_p)),     bw, 'FaceColor',[0.1 0.7 0.3],'FaceAlpha',0.7,'DisplayName','Hybrid std dev');
set(gca,'XTick',x,'XTickLabel',param_names,'FontSize',11);
ylabel('Marginal std dev','FontSize',12);
title({'Parameter marginal std devs: FIM vs LOO vs Hybrid', ...
       'Hybrid = FIM scale (target well-calibrated coverage)'},'FontSize',11,'FontWeight','bold');
legend('FontSize',10,'Location','best');
set(findall(fig_a,'Type','axes'),'Color','w');   % force light axes background
savefig_png(fig_a, fullfile(resultDir,'diag_marginal_stddev'));

% --- Fig B: LOO correlation matrix heatmap ---
fig_b = figure('Color','w','Position',[200 200 500 440]);
imagesc(results.R_loo); colorbar; caxis([-1 1]);
colormap(redblue_colormap());
set(gca,'XTick',1:n_params,'XTickLabel',param_names, ...
        'YTick',1:n_params,'YTickLabel',param_names,'FontSize',11);
% Annotate with numeric values
for ri = 1:n_params
    for ci = 1:n_params
        text(ci, ri, sprintf('%.2f', results.R_loo(ri,ci)), ...
             'HorizontalAlignment','center','FontSize',10, ...
             'Color', 'k');
    end
end
title('LOO correlation matrix R_{LOO}','FontSize',12,'FontWeight','bold');
savefig_png(fig_b, fullfile(resultDir,'diag_loo_correlation'));

% --- Fig C: Band width comparison (FIM vs Hybrid) ---
% Re-run fast_compute to get FIM-only bands for the same theta_hat
fprintf('\nComputing FIM-only bands for comparison...\n');
[UQ_l_fim, UQ_u_fim, ~, ~] = fast_compute_hybrid_uncertainty( ...
    results.media_tot, observed_data, observed_idx, ic, ...
    times, results.parameters_init, nstates, n_params, length(times), ...
    results.UQ_lower(:, observed_idx), results.UQ_upper(:, observed_idx), ...
    alp, dynamics_handle, @ODE_solve, results.options.cost, results.options.ode);

unobs_idx = find(~ismember(1:nstates, observed_idx));
for j = unobs_idx

    % Compute per-time-point band widths for the annotation panels
    w_fim = UQ_u_fim(:,j) - UQ_l_fim(:,j);
    w_hyb = results.UQ_upper(:,j) - results.UQ_lower(:,j);

    fig_c = figure('Color','w','Position',[100 100 1100 820]);

    % ----- Panel 1: FIM band -----
    ax1 = subplot(2,2,1);
    hold on; grid on;
    fill([times(:); flipud(times(:))], ...
         [UQ_l_fim(:,j); flipud(UQ_u_fim(:,j))], ...
         'r','FaceAlpha',0.30,'EdgeColor','none');
    plot(times, results.media_tot(:,j), 'k-','LineWidth',2,'DisplayName','Best fit');
    % Upper and lower edges as dashed lines for clarity
    plot(times, UQ_u_fim(:,j), 'r--','LineWidth',1,'DisplayName','FIM upper');
    plot(times, UQ_l_fim(:,j), 'r--','LineWidth',1,'DisplayName','FIM lower');
    xlabel('Time','FontSize',11); ylabel('Population','FontSize',11);
    title(sprintf('FIM 95%% CI  (mean width = %.2f)', mean(w_fim(2:end))),...
          'FontSize',11,'FontWeight','bold');
    legend('FIM band','Best fit','Location','northeast','FontSize',9);
    ylim([min(UQ_l_fim(:,j))-2, max(UQ_u_fim(:,j))+5]);

    % ----- Panel 2: Hybrid band -----
    ax2 = subplot(2,2,2);
    hold on; grid on;
    fill([times(:); flipud(times(:))], ...
         [results.UQ_lower(:,j); flipud(results.UQ_upper(:,j))], ...
         [0.1 0.65 0.3],'FaceAlpha',0.30,'EdgeColor','none');
    plot(times, results.media_tot(:,j), 'k-','LineWidth',2,'DisplayName','Best fit');
    plot(times, results.UQ_upper(:,j), '--','Color',[0.1 0.65 0.3],'LineWidth',1,'DisplayName','Hybrid upper');
    plot(times, results.UQ_lower(:,j), '--','Color',[0.1 0.65 0.3],'LineWidth',1,'DisplayName','Hybrid lower');
    xlabel('Time','FontSize',11); ylabel('Population','FontSize',11);
    title(sprintf('Hybrid 95%% CI  (mean width = %.2f)', mean(w_hyb(2:end))),...
          'FontSize',11,'FontWeight','bold');
    legend('Hybrid band','Best fit','Location','northeast','FontSize',9);
    ylim([min(UQ_l_fim(:,j))-2, max(UQ_u_fim(:,j))+5]);   % same y-scale as FIM

    % Link y-axes so visual comparison is fair
    linkaxes([ax1 ax2], 'xy');

    % ----- Panel 3: Band width over time (both methods) -----
    subplot(2,2,3);
    hold on; grid on;
    plot(times, w_fim, 'r-o','LineWidth',2,'MarkerSize',4,'DisplayName','FIM');
    plot(times, w_hyb, '-^','Color',[0.1 0.65 0.3],'LineWidth',2,'MarkerSize',4,'DisplayName','Hybrid');
    xlabel('Time','FontSize',11); ylabel('Band width','FontSize',11);
    title('Band width over time','FontSize',11,'FontWeight','bold');
    legend('FontSize',10,'Location','best');
    grid on;

    % ----- Panel 4: Ratio Hybrid/FIM width -----
    subplot(2,2,4);
    ratio_w = w_hyb ./ max(w_fim, 1e-6);
    hold on; grid on;
    plot(times, ratio_w, 'k-','LineWidth',2);
    yline(1,'r--','LineWidth',1.5,'DisplayName','Ratio = 1  (identical)');
    xlabel('Time','FontSize',11); ylabel('Width ratio Hybrid/FIM','FontSize',11);
    title({'Hybrid / FIM width ratio', ...
           '>1: Hybrid wider  |  <1: Hybrid narrower'},...
          'FontSize',11,'FontWeight','bold');
    ylim([0, max(ratio_w)*1.1 + 0.1]);
    legend('Ratio','Location','best','FontSize',10);

    sgtitle(sprintf('State %d (unobserved): FIM vs Hybrid band comparison', j), ...
            'FontSize',13,'FontWeight','bold');

    set(findall(fig_c,'Type','axes'),'Color','w');   % force light axes background
    savefig_png(fig_c, fullfile(resultDir,sprintf('diag_band_comparison_state%d',j)));
    close(fig_c);
end

fprintf('\nAll results and diagnostics saved to %s\n', resultDir);


% ====================================================================
% LOCAL: simple red-blue colormap for correlation matrix
% ====================================================================
function cmap = redblue_colormap()
    n    = 64;
    half = n/2;
    r    = [linspace(0,1,half), ones(1,half)];
    g    = [linspace(0,1,half), linspace(1,0,half)];
    b    = [ones(1,half), linspace(1,0,half)];
    cmap = [r(:), g(:), b(:)];
end
