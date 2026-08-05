%% SBC_LV2_FIM_vs_HybridCov.m
% Simulation-Based Calibration comparing FIM and HybridCov UQ methods for
% unobserved states on the Lotka-Volterra partial obs example (prey observed).
%
% METHODS COMPARED
% ----------------
%   FIM  CUQDyn1_Plus:           Cov_p solves (J'J + eps*I) Cov_p = sigma2 I
%   HYB  CUQDyn1_Plus_HybridCov: Cov_p = D_FIM * R_LOO * D_FIM
%
% Both methods run on identical synthetic datasets (same RNG seed, same
% noise draw) so coverage differences are attributable to the method.
%

clear mex; clear all; close all; clc;
addpath(genpath('../../'));

% ====================================================================
% USER CONTROL PANEL
% ====================================================================
n_sim            = 50;
noise_pct        = 10.0;
alp              = 0.025;
rng_seed         = 42;
save_all_results = false;

% --- LV problem ---
dynamics_handle    = @prob_mod_dynamics_LV;
cost_handle        = @prob_mod_cost_LV;
nstates            = 2;
n_params           = 4;
param_names        = {'alpha','beta','delta','gamma'};
true_parameters    = [0.5, 0.02, 0.02, 0.5];
initial_conditions = [10, 5];
time_points        = 0.0 : 1.0 : 30.0;
is_observed        = [1, 0];

lb_params    = true_parameters * 0.2;
ub_params    = true_parameters * 2.0;
guess_params = true_parameters * 0.8;

unobs_idx = find(~is_observed);

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
m                = length(time_points);
n_eval           = m - 1;
nominal_coverage = 1 - 2*alp;

% ====================================================================
% TRUE TRAJECTORY AND NOISE SIGMAS
% ====================================================================
options_ode = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t,y) dynamics_handle(t,y,true_parameters), ...
                     time_points, initial_conditions, options_ode);
sigma = zeros(1,nstates);
for j = 1:nstates
    if is_observed(j)
        mv = mean(Y_true(:,j));
        sigma(j) = (mv<1e-10)*1e-3 + (mv>=1e-10)*(noise_pct/100)*mv;
    end
end
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = sigma(is_observed == 1);
opts.cost.sigma_is_known = true;
meigo_opts.cost_opts = opts.cost;

% ====================================================================
% DIRECTORIES
% ====================================================================
tmpDir = 'SBC_tmp_data';
if ~exist(tmpDir,'dir'), mkdir(tmpDir); end

nowTime   = datetime('now');
timestamp = string(nowTime,'yyyy-MM-dd_HH-mm-ss');
sbcDir    = "SBC_Results_LV2_FIM_vs_HybridCov_" + timestamp;
mkdir(sbcDir);

logFile = fullfile(sbcDir,'sbc_log.txt');
fid0 = fopen(logFile,'w'); fclose(fid0);
PRINT = @(varargin) dual_print(logFile, varargin{:});

PRINT('SBC FIM vs HybridCov  ---  %s\n', timestamp);
PRINT('n_sim=%d  noise=%.0f%%  alp=%.4f\n\n', n_sim, noise_pct, alp);

% ====================================================================
% STORAGE
% ====================================================================
covered_fim = NaN(n_sim, n_eval);
covered_hyb = NaN(n_sim, n_eval);
width_fim   = NaN(n_sim, n_eval);
width_hyb   = NaN(n_sim, n_eval);

params_fim  = NaN(n_sim, n_params);
params_hyb  = NaN(n_sim, n_params);

D_fim_all   = NaN(n_sim, n_params);
D_hyb_all   = NaN(n_sim, n_params);

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
    Y_noisy = Y_true;
    for j = 1:nstates
        if is_observed(j)
            Y_noisy(2:end,j) = Y_true(2:end,j) + sigma(j)*randn(m-1,1);
            Y_noisy(Y_noisy(:,j)<0,j) = 0;
        end
    end
    data_matrix = [time_points(:), Y_noisy];
    for j = 1:nstates
        if ~is_observed(j), data_matrix(2:end,j+1) = NaN; end
    end

    tmp_csv = fullfile(tmpDir, sprintf('lv_sbc_rep%03d.csv',s));
    hdrs    = [{'time'}, arrayfun(@(j) sprintf('y%d',j),1:nstates,'UniformOutput',false)];
    writetable(array2table(data_matrix,'VariableNames',hdrs), tmp_csv);

    [times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep] = ...
        loadStateData(tmpDir, sprintf('lv_sbc_rep%03d.csv',s), nstates);

    % ------------------------------------------------------------------
    % STEP 2: FIM  (CUQDyn1_Plus)
    % ------------------------------------------------------------------
    repDir_fim = fullfile(sbcDir, sprintf('rep%03d_FIM',s));
    mkdir(repDir_fim);
    try
        res_fim = CUQDyn1_Plus( ...
            cost_handle, dynamics_handle, nstates, n_params, ...
            guess_params, lb_params, ub_params, alp, ...
            times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep, ...
            repDir_fim, meigo_opts);
        params_fim(s,:) = res_fim.parameters_init;
        D_fim_all(s,:)  = sqrt(diag(res_fim.Cov_p))';
        for j = unobs_idx
            lo = res_fim.UQ_lower(2:end,j); hi = res_fim.UQ_upper(2:end,j);
            covered_fim(s,:) = (Y_true(2:end,j)>=lo) & (Y_true(2:end,j)<=hi);
            width_fim(s,:)   = hi - lo;
        end
        PRINT('  [FIM] coverage=%.1f%%  mean_width=%.3f\n', ...
              mean(covered_fim(s,:),'omitnan')*100, mean(width_fim(s,:),'omitnan'));
    catch ME
        PRINT('  [FIM] FAILED: %s\n', ME.message);
    end

    % ------------------------------------------------------------------
    % STEP 3: Hybrid  (CUQDyn1_Plus_HybridCov)
    % ------------------------------------------------------------------
    repDir_hyb = fullfile(sbcDir, sprintf('rep%03d_HYB',s));
    mkdir(repDir_hyb);
    try
        res_hyb = CUQDyn1_Plus_HybridCov( ...
            cost_handle, dynamics_handle, nstates, n_params, ...
            guess_params, lb_params, ub_params, alp, ...
            times_rep, all_state_rep, ic_rep, obs_data_rep, obs_idx_rep, ...
            repDir_hyb, meigo_opts);
        params_hyb(s,:) = res_hyb.parameters_init;
        D_hyb_all(s,:)  = sqrt(diag(res_hyb.Cov_p))';
        for j = unobs_idx
            lo = res_hyb.UQ_lower(2:end,j); hi = res_hyb.UQ_upper(2:end,j);
            covered_hyb(s,:) = (Y_true(2:end,j)>=lo) & (Y_true(2:end,j)<=hi);
            width_hyb(s,:)   = hi - lo;
        end
        PRINT('  [HYB] coverage=%.1f%%  mean_width=%.3f\n', ...
              mean(covered_hyb(s,:),'omitnan')*100, mean(width_hyb(s,:),'omitnan'));
    catch ME
        PRINT('  [HYB] FAILED: %s\n', ME.message);
    end

    PRINT('  Replicate %d done in %.1f s\n\n', s, toc(t_rep));

end

fprintf('\nTotal SBC time: %.1f min\n', toc(t_loop_start)/60);

% ====================================================================
% SUMMARY STATISTICS
% ====================================================================
ptwise_fim = mean(covered_fim, 2, 'omitnan');
ptwise_hyb = mean(covered_hyb, 2, 'omitnan');

simult_fim = all(covered_fim,2) & ~any(isnan(covered_fim),2);
simult_hyb = all(covered_hyb,2) & ~any(isnan(covered_hyb),2);

pt_by_time_fim = mean(covered_fim, 1, 'omitnan');
pt_by_time_hyb = mean(covered_hyb, 1, 'omitnan');

fprintf('\n%s\n SBC: FIM vs HybridCov — Lotka-Volterra\n%s\n', ...
        repmat('=',1,60), repmat('=',1,60));
fprintf('Nominal coverage: %.1f%%\n\n', nominal_coverage*100);

for method = {'FIM','HYB'}
    name = method{1};
    switch name
        case 'FIM'; ptw=ptwise_fim; sim=simult_fim; wid=width_fim; D_m=D_fim_all;
        case 'HYB'; ptw=ptwise_hyb; sim=simult_hyb; wid=width_hyb; D_m=D_hyb_all;
    end
    fprintf('--- %s ---\n', name);
    fprintf('  Mean pointwise coverage:    %.1f%%\n', mean(ptw,'omitnan')*100);
    fprintf('  Std  pointwise coverage:    %.1f%%\n', std(ptw,'omitnan')*100);
    fprintf('  Simultaneous coverage:      %.1f%%\n', mean(sim)*100);
    fprintf('  Mean band width (predator): %.4f\n',   mean(wid(:),'omitnan'));
    fprintf('  Mean marginal std devs:     %s\n\n',   num2str(mean(D_m,1,'omitnan'),'%.4g '));
end

% ====================================================================
% FIGURES
% ====================================================================
t_eval = time_points(2:end);

% --- Fig 1: Pointwise coverage by time ---
fig1 = figure('Color','w','Position',[50 50 900 400]);
hold on; grid on;
plot(t_eval, pt_by_time_fim*100,'r-s','LineWidth',2,'MarkerSize',5,'DisplayName','FIM');
plot(t_eval, pt_by_time_hyb*100,'g-^','LineWidth',2,'MarkerSize',5,'DisplayName','Hybrid');
yline(nominal_coverage*100,'k--','LineWidth',2,'DisplayName',sprintf('Nominal %.0f%%',nominal_coverage*100));
ylim([0 105]); xlabel('Time','FontSize',12); ylabel('Coverage (%)','FontSize',12);
title(sprintf('Pointwise coverage — predator (unobserved)  [n=%d replicates]',n_sim), ...
      'FontSize',12,'FontWeight','bold');
legend('Location','south','FontSize',10);
savefig(fig1,fullfile(sbcDir,'fig1_coverage_by_time.fig'));
savefig_png(fig1, fullfile(sbcDir,'fig1_coverage_by_time'));

% --- Fig 2: Per-replicate coverage distributions ---
fig2 = figure('Color','w','Position',[100 100 700 400]);
hold on; grid on;
histogram(ptwise_fim*100,'BinWidth',5,'FaceColor','r','FaceAlpha',0.5,'DisplayName','FIM');
histogram(ptwise_hyb*100,'BinWidth',5,'FaceColor','g','FaceAlpha',0.5,'DisplayName','Hybrid');
xline(nominal_coverage*100,'k--','LineWidth',2);
xlabel('Pointwise coverage per replicate (%)','FontSize',12); ylabel('Count','FontSize',12);
title('Distribution of per-replicate coverage','FontSize',12,'FontWeight','bold');
legend('FontSize',10);
savefig(fig2,fullfile(sbcDir,'fig2_coverage_dist.fig'));
savefig_png(fig2, fullfile(sbcDir,'fig2_coverage_dist'));

% --- Fig 3: Mean band width by time ---
fig3 = figure('Color','w','Position',[150 150 900 400]);
hold on; grid on;
plot(t_eval,mean(width_fim,1,'omitnan'),'r-s','LineWidth',2,'MarkerSize',5,'DisplayName','FIM');
plot(t_eval,mean(width_hyb,1,'omitnan'),'g-^','LineWidth',2,'MarkerSize',5,'DisplayName','Hybrid');
xlabel('Time','FontSize',12); ylabel('Mean band width','FontSize',12);
title('Mean prediction band width — predator (unobserved)','FontSize',12,'FontWeight','bold');
legend('Location','best','FontSize',10);
savefig(fig3,fullfile(sbcDir,'fig3_band_width.fig'));
savefig_png(fig3, fullfile(sbcDir,'fig3_band_width'));

% --- Fig 4: Marginal std dev comparison across replicates ---
fig4 = figure('Color','w','Position',[200 200 1000 600]);
for p = 1:n_params
    subplot(2,2,p); hold on; grid on;
    histogram(D_fim_all(:,p),'FaceColor','r','FaceAlpha',0.5,'DisplayName','FIM');
    histogram(D_hyb_all(:,p),'FaceColor','g','FaceAlpha',0.5,'DisplayName','Hybrid');
    xlabel('Marginal std dev','FontSize',10); ylabel('Count','FontSize',10);
    title(param_names{p},'FontSize',11,'FontWeight','bold');
    if p==1, legend('FontSize',8); end
end
sgtitle('Per-parameter marginal std devs: FIM vs Hybrid','FontSize',12,'FontWeight','bold');
savefig(fig4,fullfile(sbcDir,'fig4_marginal_stdev.fig'));
savefig_png(fig4, fullfile(sbcDir,'fig4_marginal_stdev'));

% --- Fig 5: Calibration summary bar chart ---
methods    = {'FIM','Hybrid'};
cov_means  = [mean(ptwise_fim,'omitnan'), mean(ptwise_hyb,'omitnan')] * 100;
cov_stds   = [std(ptwise_fim,'omitnan'),  std(ptwise_hyb,'omitnan')]  * 100;
width_means= [mean(width_fim(:),'omitnan'), mean(width_hyb(:),'omitnan')];

fig5 = figure('Color','w','Position',[250 250 600 500]);
subplot(2,1,1); hold on; grid on;
hb = bar(1:2, cov_means, 'FaceColor','flat');
hb.CData = [0.9 0.2 0.2; 0.1 0.7 0.3];
errorbar(1:2, cov_means, cov_stds,'k.','LineWidth',1.5);
yline(nominal_coverage*100,'k--','LineWidth',2);
set(gca,'XTick',1:2,'XTickLabel',methods,'FontSize',11);
ylabel('Mean ptwise coverage (%)','FontSize',11);
title('Coverage calibration summary','FontSize',11,'FontWeight','bold');
ylim([0 105]);

subplot(2,1,2); hold on; grid on;
hb2 = bar(1:2, width_means, 'FaceColor','flat');
hb2.CData = [0.9 0.2 0.2; 0.1 0.7 0.3];
set(gca,'XTick',1:2,'XTickLabel',methods,'FontSize',11);
ylabel('Mean band width (predator)','FontSize',11);
title('Mean prediction band width','FontSize',11,'FontWeight','bold');

sgtitle('SBC comparison — Lotka-Volterra','FontSize',12,'FontWeight','bold');
savefig(fig5,fullfile(sbcDir,'fig5_summary.fig'));
savefig_png(fig5, fullfile(sbcDir,'fig5_summary'));

% ====================================================================
% SAVE WORKSPACE
% ====================================================================
save(fullfile(sbcDir,'SBC_workspace.mat'), ...
     'covered_fim','covered_hyb', ...
     'width_fim','width_hyb', ...
     'ptwise_fim','ptwise_hyb', ...
     'simult_fim','simult_hyb', ...
     'pt_by_time_fim','pt_by_time_hyb', ...
     'D_fim_all','D_hyb_all', ...
     'params_fim','params_hyb', ...
     'true_parameters','nominal_coverage','n_sim','alp', ...
     'time_points','param_names','lb_params','ub_params');

fprintf('All results saved to  %s\n', sbcDir);
fprintf('Log written to        %s\n', logFile);

% ====================================================================
% LOCAL FUNCTION
% ====================================================================
function dual_print(logpath, varargin)
    str = sprintf(varargin{:});
    fprintf('%s', str);
    fid = fopen(logpath,'a');
    if fid > 0, fprintf(fid,'%s',str); fclose(fid); end
end
