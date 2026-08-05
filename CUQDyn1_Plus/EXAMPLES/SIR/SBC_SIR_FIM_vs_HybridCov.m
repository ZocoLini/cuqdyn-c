%% SBC_SIR_FIM_vs_HybridCov.m
%
% Simulation-Based Calibration for the SIR epidemic partial observability
% example, comparing the two most competitive methods:
%
%   FIM     CUQDyn1_Plus:           Cov_p solves (J'J + eps*I) Cov_p = sigma2 I
%   HYB     CUQDyn1_Plus_HybridCov: Cov_p = D_FIM * R_LOO * D_FIM
%
% PROBLEM SETUP
% -------------
%   3 states, 2 parameters (beta, gamma)
%   State 2 (Infected) observed; States 1 (Susceptible) and 3 (Recovered)
%   unobserved after t=0.  Initial conditions known for all states.
%   alp = 0.05  =>  nominal 1-2*alp = 90% two-sided coverage
%   Time grid: 0 to 15 days in steps of 0.5 (31 points, built inline)
%
% NOISE MODEL
% -----------
%   Proportional Gaussian noise on observed state (Infected) only:
%       sigma = (noise_pct/100) * mean(I*(t_2,...,t_n))
%   Noise applied at t_2,...,t_n only; t=0 IC is kept exact.
%   Matches the noise model in run_SIR_CUQDyn1Plus.m exactly.
%
% COVERAGE TRACKING
% -----------------
%   Both unobserved states (S and R) are tracked independently.
%   All figures show results per state so that differences in band
%   behaviour between the monotone-decreasing S and monotone-increasing R
%   are visible.
%
% Both methods run on identical synthetic datasets (same RNG seed per
% replicate) so all coverage differences are attributable to the method.
%
% OUTPUT
%   sbcDir/  — timestamped directory containing:
%     fig1_coverage_by_time.png      pointwise coverage vs time, per state
%     fig2_coverage_dist.png         per-replicate coverage histograms
%     fig3_band_width.png            mean band width vs time, per state
%     fig4_param_recovery.png        parameter estimate distributions
%     fig5_marginal_stddev.png       FIM vs LOO vs Hybrid marginal std devs
%     fig6_loo_correlation.png       LOO correlation matrix (last replicate)
%     fig7_summary.png               calibration summary bar chart
%     SBC_SIR_workspace.mat          full workspace for post-hoc analysis
%     sbc_log.txt                    per-replicate verbose log
%

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% ====================================================================
% USER CONTROL PANEL
% ====================================================================
n_sim          = 50;
noise_pct      = 10.0;    % proportional noise on observed state (%)
rng_seed       = 42;
bound_tol_frac = 0.02;    % bound proximity threshold for optimizer diagnostics

% --- SIR problem (must match run_SIR scripts exactly) ---
dynamics_handle = @prob_mod_dynamics_SIR;
cost_handle     = @prob_mod_cost_SIR;
nstates         = 3;
n_params        = 2;
param_names     = {'beta','gamma'};
true_parameters = [0.002, 0.5];
initial_conditions = [990, 10, 0];
times           = (0 : 0.5 : 15)';   % 31 points

lb_params    = [0.0001, 0.01];
ub_params    = [0.01,   2.0];
guess_params = [0.001,  0.2];
alp          = 0.05;   % 90% nominal two-sided coverage

% Observability: only state 2 (Infected) observed
is_observed = [0, 1, 0];
obs_idx     = find( is_observed);   % = 2
unobs_idx   = find(~is_observed);   % = [1, 3]
unobs_names = {'Susceptible','Recovered'};

% Optimiser / integration defaults for calibration runs.
opts = cuqdyn_default_options(n_params, 'sbc');
opts.uq.alp = alp;
opts.ode.RelTol = 1e-9;
opts.ode.AbsTol = 1e-11;
cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;

% ====================================================================
% DERIVED QUANTITIES
% ====================================================================
nominal_coverage = 1 - 2*alp;
bound_range      = ub_params - lb_params;
m                = length(times);
n_eval           = m - 1;          % evaluation points (t_2 ... t_n)
n_loo_folds      = m - 1;
n_unobs          = length(unobs_idx);   % 2

% ====================================================================
% TRUE TRAJECTORY AND NOISE SIGMA
% ====================================================================
options_ode = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t,y) dynamics_handle(t,y,true_parameters), ...
                     times, initial_conditions, options_ode);

% Proportional sigma on observed state only (mean over t_2,...,t_n)
sigma_obs = (noise_pct/100) * mean(Y_true(2:end, obs_idx));
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = sigma_obs;
opts.cost.sigma_is_known = true;
meigo_opts.cost_opts = opts.cost;

fprintf('SIR SBC setup:\n');
fprintf('  Time points : %d  (t=%.1f to %.1f days)\n', m, times(1), times(end));
fprintf('  Observed    : state %d (%s)\n', obs_idx, 'Infected');
fprintf('  Unobserved  : states %s\n', num2str(unobs_idx));
fprintf('  Noise sigma : %.4f  (%.0f%% proportional)\n', sigma_obs, noise_pct);
fprintf('  Nominal cov : %.0f%%\n\n', nominal_coverage*100);

% ====================================================================
% DIRECTORIES AND LOG
% ====================================================================
tmpDir = 'SBC_SIR_tmp_data';
if ~exist(tmpDir,'dir'), mkdir(tmpDir); end

nowTime   = datetime('now');
timestamp = string(nowTime,'yyyy-MM-dd_HH-mm-ss');
sbcDir    = "SBC_Results_SIR_FIM_vs_HybridCov_" + timestamp;
mkdir(sbcDir);

logFile = fullfile(sbcDir,'sbc_log.txt');
fid0 = fopen(logFile,'w'); fclose(fid0);
PRINT = @(varargin) dual_print(logFile, varargin{:});

PRINT('SBC: SIR FIM vs HybridCov  ---  %s\n', timestamp);
PRINT('n_sim=%d  noise=%.0f%%  alp=%.4f  nominal=%.0f%%\n\n', ...
      n_sim, noise_pct, alp, nominal_coverage*100);

% ====================================================================
% STORAGE ARRAYS
% ====================================================================
% Coverage and width: [n_sim x n_eval] per unobserved state.
% Indexed as covered_fim{k}, width_fim{k} for unobs_idx(k).
covered_fim = cell(n_unobs,1);
covered_hyb = cell(n_unobs,1);
width_fim   = cell(n_unobs,1);
width_hyb   = cell(n_unobs,1);
for k = 1:n_unobs
    covered_fim{k} = NaN(n_sim, n_eval);
    covered_hyb{k} = NaN(n_sim, n_eval);
    width_fim{k}   = NaN(n_sim, n_eval);
    width_hyb{k}   = NaN(n_sim, n_eval);
end

% Full-data parameter estimates per replicate
params_fim = NaN(n_sim, n_params);
params_hyb = NaN(n_sim, n_params);

% Covariance diagnostics
D_fim_all = NaN(n_sim, n_params);   % FIM marginal std devs
D_hyb_all = NaN(n_sim, n_params);   % Hybrid marginal std devs (= D_fim)
D_loo_all = NaN(n_sim, n_params);   % LOO marginal std devs (from Hybrid run)

% LOO optimizer diagnostics
loo_any_bound_hit = false(n_sim, n_loo_folds);

% Last replicate LOO correlation matrix (for Fig 6)
R_loo_last = NaN(n_params, n_params);

% ====================================================================
% MAIN SBC LOOP
% ====================================================================
rng(rng_seed);
PRINT('=== Starting SBC: %d replicates ===\n\n', n_sim);
t_loop_start = tic;

for s = 1:n_sim

    PRINT('%s\n', repmat('=',1,60));
    PRINT('REPLICATE %d / %d\n', s, n_sim);
    PRINT('%s\n', repmat('=',1,60));
    t_rep = tic;

    % ------------------------------------------------------------------
    % STEP 1: Generate synthetic dataset
    % ------------------------------------------------------------------
    % Proportional noise on observed state (Infected), t_2 onward only
    y_obs            = Y_true(:, obs_idx);
    y_obs(2:end)     = Y_true(2:end, obs_idx) + sigma_obs * randn(n_eval, 1);
    y_obs            = max(0, y_obs);

    % all_state_data: NaN for unobserved states after t=0; exact ICs row 1
    data_matrix            = NaN(m, nstates);
    data_matrix(1, :)      = initial_conditions;   % exact ICs
    data_matrix(:, obs_idx) = y_obs;               % row 1 stays exact

    % Write to temporary CSV for loadStateData
    tmp_csv = fullfile(tmpDir, sprintf('sir_sbc_rep%03d.csv', s));
    hdrs    = [{'time'}, arrayfun(@(j) sprintf('y%d',j), 1:nstates, 'UniformOutput',false)];
    writetable(array2table([times, data_matrix], 'VariableNames', hdrs), tmp_csv);

    [times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep] = ...
        loadStateData(tmpDir, sprintf('sir_sbc_rep%03d.csv',s), nstates);

    % ------------------------------------------------------------------
    % STEP 2: FIM  (CUQDyn1_Plus)
    % ------------------------------------------------------------------
    repDir_fim = fullfile(sbcDir, sprintf('rep%03d_FIM', s));
    mkdir(repDir_fim);
    try
        res_fim = CUQDyn1_Plus( ...
            cost_handle, dynamics_handle, nstates, n_params, ...
            guess_params, lb_params, ub_params, alp, ...
            times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep, ...
            repDir_fim, meigo_opts);

        params_fim(s,:) = res_fim.parameters_init;
        D_fim_all(s,:)  = sqrt(diag(res_fim.Cov_p))';

        % Coverage and width per unobserved state
        for ki = 1:n_unobs
            j  = unobs_idx(ki);
            lo = res_fim.UQ_lower(2:end, j);
            hi = res_fim.UQ_upper(2:end, j);
            covered_fim{ki}(s,:) = (Y_true(2:end,j) >= lo) & (Y_true(2:end,j) <= hi);
            width_fim{ki}(s,:)   = hi - lo;
        end

        J_fim = sum((obs_data_rep - res_fim.media_tot(:,obs_idx_rep)).^2,'all');
        cov_s = arrayfun(@(ki) mean(covered_fim{ki}(s,:),'omitnan')*100, 1:n_unobs);
        PRINT('  [FIM] J=%.6f  cov S=%.1f%%  cov R=%.1f%%\n', J_fim, cov_s(1), cov_s(2));

        % Per-parameter relative errors
        PRINT('  [FIM] RelErr%%: ');
        for p = 1:n_params
            PRINT('%s=%.2f%% ', param_names{p}, ...
                  100*abs(res_fim.parameters_init(p)-true_parameters(p))/true_parameters(p));
        end
        PRINT('\n');

    catch ME
        PRINT('  [FIM] FAILED: %s\n', ME.message);
    end

    % ------------------------------------------------------------------
    % STEP 3: HYBRID  (CUQDyn1_Plus_HybridCov)
    % ------------------------------------------------------------------
    repDir_hyb = fullfile(sbcDir, sprintf('rep%03d_HYB', s));
    mkdir(repDir_hyb);
    try
        res_hyb = CUQDyn1_Plus_HybridCov( ...
            cost_handle, dynamics_handle, nstates, n_params, ...
            guess_params, lb_params, ub_params, alp, ...
            times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep, ...
            repDir_hyb, meigo_opts);

        params_hyb(s,:) = res_hyb.parameters_init;
        D_hyb_all(s,:)  = sqrt(diag(res_hyb.Cov_p))';
        D_loo_all(s,:)  = sqrt(diag(res_hyb.Cov_p_loo))';

        % LOO optimizer diagnostics
        lp      = res_hyb.loo_params;
        n_folds = size(lp,1);
        for f = 1:n_folds
            near_lb = (lp(f,:) - lb_params) ./ bound_range < bound_tol_frac;
            near_ub = (ub_params - lp(f,:)) ./ bound_range < bound_tol_frac;
            loo_any_bound_hit(s,f) = any(near_lb | near_ub);
        end

        % Coverage and width per unobserved state
        for ki = 1:n_unobs
            j  = unobs_idx(ki);
            lo = res_hyb.UQ_lower(2:end, j);
            hi = res_hyb.UQ_upper(2:end, j);
            covered_hyb{ki}(s,:) = (Y_true(2:end,j) >= lo) & (Y_true(2:end,j) <= hi);
            width_hyb{ki}(s,:)   = hi - lo;
        end

        J_hyb = sum((obs_data_rep - res_hyb.media_tot(:,obs_idx_rep)).^2,'all');
        cov_s = arrayfun(@(ki) mean(covered_hyb{ki}(s,:),'omitnan')*100, 1:n_unobs);
        PRINT('  [HYB] J=%.6f  cov S=%.1f%%  cov R=%.1f%%\n', J_hyb, cov_s(1), cov_s(2));
        PRINT('  [HYB] LOO bound-hit rate: %.1f%%  R_LOO(1,2)=%.3f\n', ...
              mean(loo_any_bound_hit(s,1:n_folds))*100, res_hyb.R_loo(1,2));

        R_loo_last = res_hyb.R_loo;

    catch ME
        PRINT('  [HYB] FAILED: %s\n', ME.message);
    end

    PRINT('  Replicate %d done in %.1f s\n\n', s, toc(t_rep));

end   % end SBC loop

fprintf('\nTotal SBC time: %.1f min\n', toc(t_loop_start)/60);

% ====================================================================
% SUMMARY STATISTICS  (computed per unobserved state)
% ====================================================================
ptwise_fim = cellfun(@(C) mean(C, 2, 'omitnan'), covered_fim, 'UniformOutput',false);
ptwise_hyb = cellfun(@(C) mean(C, 2, 'omitnan'), covered_hyb, 'UniformOutput',false);

simult_fim = cellfun(@(C) all(C,2) & ~any(isnan(C),2), covered_fim, 'UniformOutput',false);
simult_hyb = cellfun(@(C) all(C,2) & ~any(isnan(C),2), covered_hyb, 'UniformOutput',false);

pt_by_time_fim = cellfun(@(C) mean(C,1,'omitnan'), covered_fim, 'UniformOutput',false);
pt_by_time_hyb = cellfun(@(C) mean(C,1,'omitnan'), covered_hyb, 'UniformOutput',false);

overall_bound_hit = mean(loo_any_bound_hit(:),'omitnan') * 100;

PRINT('\n%s\n', repmat('=',1,60));
PRINT(' SBC SUMMARY — SIR FIM vs HybridCov\n');
PRINT('%s\n', repmat('=',1,60));
PRINT('Nominal coverage: %.0f%%\n\n', nominal_coverage*100);

for method = {'FIM','HYB'}
    name = method{1};
    PRINT('--- %s ---\n', name);
    for ki = 1:n_unobs
        j = unobs_idx(ki);
        switch name
            case 'FIM'
                ptw = ptwise_fim{ki}; sim = simult_fim{ki};
                wid = width_fim{ki};
            case 'HYB'
                ptw = ptwise_hyb{ki}; sim = simult_hyb{ki};
                wid = width_hyb{ki};
        end
        PRINT('  State %d (%s):\n', j, unobs_names{ki});
        PRINT('    Mean ptwise coverage : %.1f%%\n',  mean(ptw,'omitnan')*100);
        PRINT('    Std  ptwise coverage : %.1f%%\n',  std(ptw,'omitnan')*100);
        PRINT('    Simultaneous coverage: %.1f%%\n',  mean(sim)*100);
        PRINT('    Mean band width      : %.4f\n',    mean(wid(:),'omitnan'));
    end
    PRINT('\n');
end
PRINT('LOO overall bound-hit rate (HYB runs): %.2f%%\n', overall_bound_hit);
PRINT('\nAll results saved to: %s\n', sbcDir);

% ====================================================================
% FIGURES
% ====================================================================
t_eval    = times(2:end);
col_fim   = [0.85 0.15 0.15];
col_hyb   = [0.10 0.65 0.20];
nom_line  = nominal_coverage * 100;
methods_lbl = {'FIM','Hybrid'};

% State colours for multi-state panels
state_cols = {[0.2 0.4 0.8], [0.8 0.4 0.2]};   % blue=S, orange=R

% --- Fig 1: Pointwise coverage by time, one subplot per unobserved state ---
fig1 = figure('Color','w','Position',[50 50 1100 420]);
for ki = 1:n_unobs
    j = unobs_idx(ki);
    subplot(1, n_unobs, ki); hold on; grid on;
    plot(t_eval, pt_by_time_fim{ki}*100, '-s','Color',col_fim, ...
         'LineWidth',2,'MarkerSize',5,'DisplayName','FIM');
    plot(t_eval, pt_by_time_hyb{ki}*100, '-^','Color',col_hyb, ...
         'LineWidth',2,'MarkerSize',5,'DisplayName','Hybrid');
    yline(nom_line,'k--','LineWidth',2,'DisplayName',sprintf('Nominal %.0f%%',nom_line));
    ylim([0 105]);
    xlabel('Time (days)','FontSize',11);
    ylabel('Coverage (%)','FontSize',11);
    title(sprintf('State %d: %s', j, unobs_names{ki}),'FontSize',11,'FontWeight','bold');
    if ki==1, legend('Location','south','FontSize',10); end
end
sgtitle(sprintf('Pointwise coverage by time  [n=%d replicates]', n_sim), ...
        'FontSize',12,'FontWeight','bold');
savefig(fig1, fullfile(sbcDir,'fig1_coverage_by_time.fig'));
savefig_png(fig1,  fullfile(sbcDir,'fig1_coverage_by_time'));

% --- Fig 2: Per-replicate coverage distributions ---
fig2 = figure('Color','w','Position',[100 100 1000 420]);
for ki = 1:n_unobs
    j = unobs_idx(ki);
    subplot(1, n_unobs, ki); hold on; grid on;
    histogram(ptwise_fim{ki}*100,'BinWidth',5,'FaceColor',col_fim, ...
              'FaceAlpha',0.6,'DisplayName','FIM');
    histogram(ptwise_hyb{ki}*100,'BinWidth',5,'FaceColor',col_hyb, ...
              'FaceAlpha',0.6,'DisplayName','Hybrid');
    xline(nom_line,'k--','LineWidth',2,'DisplayName',sprintf('Nominal %.0f%%',nom_line));
    xlabel('Coverage per replicate (%)','FontSize',11);
    ylabel('Count','FontSize',11);
    title(sprintf('State %d: %s', j, unobs_names{ki}),'FontSize',11,'FontWeight','bold');
    if ki==1, legend('Location','northwest','FontSize',10); end
end
sgtitle('Distribution of per-replicate pointwise coverage','FontSize',12,'FontWeight','bold');
savefig(fig2, fullfile(sbcDir,'fig2_coverage_dist.fig'));
savefig_png(fig2,  fullfile(sbcDir,'fig2_coverage_dist'));

% --- Fig 3: Mean band width by time ---
fig3 = figure('Color','w','Position',[150 150 1100 420]);
for ki = 1:n_unobs
    j = unobs_idx(ki);
    subplot(1, n_unobs, ki); hold on; grid on;
    plot(t_eval, mean(width_fim{ki},1,'omitnan'), '-s','Color',col_fim, ...
         'LineWidth',2,'MarkerSize',5,'DisplayName','FIM');
    plot(t_eval, mean(width_hyb{ki},1,'omitnan'), '-^','Color',col_hyb, ...
         'LineWidth',2,'MarkerSize',5,'DisplayName','Hybrid');
    xlabel('Time (days)','FontSize',11);
    ylabel('Mean band width','FontSize',11);
    title(sprintf('State %d: %s', j, unobs_names{ki}),'FontSize',11,'FontWeight','bold');
    if ki==1, legend('Location','best','FontSize',10); end
end
sgtitle('Mean prediction band width over time','FontSize',12,'FontWeight','bold');
savefig(fig3, fullfile(sbcDir,'fig3_band_width.fig'));
savefig_png(fig3,  fullfile(sbcDir,'fig3_band_width'));

% --- Fig 4: Parameter recovery ---
fig4 = figure('Color','w','Position',[200 200 700 340]);
for p = 1:n_params
    subplot(1, n_params, p); hold on; grid on;
    histogram(params_fim(:,p),'FaceColor',col_fim,'FaceAlpha',0.6,'DisplayName','FIM');
    histogram(params_hyb(:,p),'FaceColor',col_hyb,'FaceAlpha',0.6,'DisplayName','Hybrid');
    xline(true_parameters(p),'k--','LineWidth',2,'DisplayName','True');
    xlabel('Estimate','FontSize',10); ylabel('Count','FontSize',10);
    title(param_names{p},'FontSize',11,'FontWeight','bold');
    if p==1, legend('FontSize',9,'Location','best'); end
end
sgtitle('Full-data parameter recovery across SBC replicates', ...
        'FontSize',12,'FontWeight','bold');
savefig(fig4, fullfile(sbcDir,'fig4_param_recovery.fig'));
savefig_png(fig4,  fullfile(sbcDir,'fig4_param_recovery'));

% --- Fig 5: Marginal std dev comparison ---
fig5 = figure('Color','w','Position',[250 250 600 340]);
hold on; grid on;
x_pos = 1:n_params;
bw    = 0.25;
bar(x_pos - bw, mean(D_fim_all,1,'omitnan'), bw, ...
    'FaceColor',col_fim,'FaceAlpha',0.8,'DisplayName','FIM');
bar(x_pos,      mean(D_loo_all,1,'omitnan'), bw, ...
    'FaceColor',[0.2 0.3 0.9],'FaceAlpha',0.8,'DisplayName','LOO');
bar(x_pos + bw, mean(D_hyb_all,1,'omitnan'), bw, ...
    'FaceColor',col_hyb,'FaceAlpha',0.8,'DisplayName','Hybrid');
set(gca,'XTick',x_pos,'XTickLabel',param_names,'FontSize',12);
ylabel('Mean marginal std dev','FontSize',12);
title({'Parameter marginal std devs: FIM vs LOO vs Hybrid', ...
       'Hybrid inherits FIM scale by construction'},'FontSize',11,'FontWeight','bold');
legend('FontSize',10,'Location','best');
savefig(fig5, fullfile(sbcDir,'fig5_marginal_stddev.fig'));
savefig_png(fig5,  fullfile(sbcDir,'fig5_marginal_stddev'));

% --- Fig 6: LOO correlation matrix (last successful replicate) ---
if ~any(isnan(R_loo_last(:)))
    fig6 = figure('Color','w','Position',[300 300 400 360]);
    imagesc(R_loo_last); colorbar; caxis([-1 1]);
    colormap(sbc_redblue(64));
    set(gca,'XTick',1:n_params,'XTickLabel',param_names, ...
            'YTick',1:n_params,'YTickLabel',param_names,'FontSize',13);
    for ri = 1:n_params
        for ci = 1:n_params
            text(ci, ri, sprintf('%.3f', R_loo_last(ri,ci)), ...
                 'HorizontalAlignment','center','FontSize',12,'Color','k');
        end
    end
    title('LOO correlation matrix R_{LOO} (last replicate)', ...
          'FontSize',12,'FontWeight','bold');
    savefig(fig6, fullfile(sbcDir,'fig6_loo_correlation.fig'));
    savefig_png(fig6,  fullfile(sbcDir,'fig6_loo_correlation'));
end

% --- Fig 7: Calibration summary (one column pair per unobserved state) ---
% Three rows: pointwise coverage, simultaneous coverage, mean band width.
fig7 = figure('Color','w','Position',[100 50 900 700]);
bar_labels = {};
cov_pt_means  = zeros(2, n_unobs);   % rows = [FIM; HYB]
cov_pt_stds   = zeros(2, n_unobs);
cov_sim_means = zeros(2, n_unobs);
wid_means     = zeros(2, n_unobs);

for ki = 1:n_unobs
    cov_pt_means(1,ki) = mean(ptwise_fim{ki},'omitnan')*100;
    cov_pt_means(2,ki) = mean(ptwise_hyb{ki},'omitnan')*100;
    cov_pt_stds(1,ki)  = std(ptwise_fim{ki},'omitnan')*100;
    cov_pt_stds(2,ki)  = std(ptwise_hyb{ki},'omitnan')*100;
    cov_sim_means(1,ki)= mean(simult_fim{ki})*100;
    cov_sim_means(2,ki)= mean(simult_hyb{ki})*100;
    wid_means(1,ki)    = mean(width_fim{ki}(:),'omitnan');
    wid_means(2,ki)    = mean(width_hyb{ki}(:),'omitnan');
    bar_labels{end+1}  = sprintf('S%d-%s FIM',  unobs_idx(ki), unobs_names{ki}(1:3)); %#ok<SAGROW>
    bar_labels{end+1}  = sprintf('S%d-%s Hyb',  unobs_idx(ki), unobs_names{ki}(1:3)); %#ok<SAGROW>
end

% Flatten for grouped bar chart: [n_unobs*2 x 1] vectors
pt_flat  = reshape(cov_pt_means,  [], 1);
pts_flat = reshape(cov_pt_stds,   [], 1);
sim_flat = reshape(cov_sim_means, [], 1);
wid_flat = reshape(wid_means,     [], 1);
colors_rep = repmat([col_fim; col_hyb], n_unobs, 1);

subplot(3,1,1); hold on; grid on;
hb1 = bar(1:2*n_unobs, pt_flat, 'FaceColor','flat');
for b = 1:2*n_unobs, hb1.CData(b,:) = colors_rep(b,:); end
errorbar(1:2*n_unobs, pt_flat, pts_flat,'k.','LineWidth',1.5,'CapSize',6);
yline(nom_line,'k--','LineWidth',1.5,'DisplayName',sprintf('Nominal %.0f%%',nom_line));
set(gca,'XTick',1:2*n_unobs,'XTickLabel',bar_labels,'FontSize',9);
ylabel('Mean ptwise cov. (%)','FontSize',10);
title('Pointwise coverage (mean ± std)','FontSize',11,'FontWeight','bold');
ylim([0 105]);

subplot(3,1,2); hold on; grid on;
hb2 = bar(1:2*n_unobs, sim_flat, 'FaceColor','flat');
for b = 1:2*n_unobs, hb2.CData(b,:) = colors_rep(b,:); end
set(gca,'XTick',1:2*n_unobs,'XTickLabel',bar_labels,'FontSize',9);
ylabel('Simult. cov. (%)','FontSize',10);
title('Simultaneous coverage','FontSize',11,'FontWeight','bold');
ylim([0 105]);

subplot(3,1,3); hold on; grid on;
hb3 = bar(1:2*n_unobs, wid_flat, 'FaceColor','flat');
for b = 1:2*n_unobs, hb3.CData(b,:) = colors_rep(b,:); end
set(gca,'XTick',1:2*n_unobs,'XTickLabel',bar_labels,'FontSize',9);
ylabel('Mean band width','FontSize',10);
title('Mean prediction band width','FontSize',11,'FontWeight','bold');

sgtitle(sprintf('SBC summary — SIR example  (n=%d, nominal %.0f%%)', ...
                n_sim, nom_line),'FontSize',12,'FontWeight','bold');
savefig(fig7, fullfile(sbcDir,'fig7_summary.fig'));
savefig_png(fig7,  fullfile(sbcDir,'fig7_summary'));

% ====================================================================
% SAVE WORKSPACE
% ====================================================================
save(fullfile(sbcDir,'SBC_SIR_workspace.mat'), ...
     'covered_fim','covered_hyb', ...
     'width_fim','width_hyb', ...
     'ptwise_fim','ptwise_hyb', ...
     'simult_fim','simult_hyb', ...
     'pt_by_time_fim','pt_by_time_hyb', ...
     'D_fim_all','D_hyb_all','D_loo_all', ...
     'params_fim','params_hyb', ...
     'loo_any_bound_hit','R_loo_last', ...
     'true_parameters','nominal_coverage','n_sim','alp', ...
     'times','param_names','lb_params','ub_params', ...
     'is_observed','obs_idx','unobs_idx','unobs_names', ...
     'Y_true','sigma_obs','initial_conditions');

fprintf('All results saved to  %s\n', sbcDir);
fprintf('Log written to        %s\n', logFile);

% ====================================================================
% LOCAL FUNCTIONS
% ====================================================================
function dual_print(logpath, varargin)
% Write to console and append to log file atomically.
    str = sprintf(varargin{:});
    fprintf('%s', str);
    fid = fopen(logpath,'a');
    if fid > 0, fprintf(fid,'%s',str); fclose(fid); end
end

function cmap = sbc_redblue(n)
% Red-white-blue diverging colormap for LOO correlation heatmap.
    half = floor(n/2);
    r = [ones(1,half),       linspace(1,0,n-half)];
    g = [linspace(0,1,half), linspace(1,0,n-half)];
    b = [linspace(0,1,half), ones(1,n-half)];
    cmap = [r(:), g(:), b(:)];
end
