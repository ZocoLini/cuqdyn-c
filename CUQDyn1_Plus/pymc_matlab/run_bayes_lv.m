%% run_bayes_lv.m
% Calls the Python ABC-SMC script for Lotka-Volterra and plots results.
%
% Model: dy1/dt = (alpha - beta*y2)*y1  [prey, OBSERVED]
%        dy2/dt = (delta*y1 - gamma)*y2 [predator, UNOBSERVED]
%
% Inferred parameters: alpha, beta, delta, gamma
% Data: ../EXAMPLES/LV/data/lv2_synthetic_data_noi10_partobs_1.csv
%
% Run this script from within the pymc_matlab/ directory.

%% -- 0. Pre-flight: verify shared data CSV exists -------------------------
dataCSV = fullfile('..', 'EXAMPLES', 'LV', 'data', ...
    'lv2_synthetic_data_noi10_partobs_1.csv');
if ~isfile(dataCSV)
    error(['LV data CSV not found:\n  %s\n' ...
           'Regenerate it with EXAMPLES/LV/data_generation/generateSyntheticData_LV.m.'], dataCSV);
end

%% ── 1. Configuration ────────────────────────────────────────────────────
pythonScript = 'lv_pymc.py';
resultsDir   = fullfile('results', 'lv');
true_vals    = [0.5, 0.02, 0.02, 0.5];   % alpha, beta, delta, gamma

%% ── 2. Run Python via uv ────────────────────────────────────────────────
fprintf('Running Python ABC-SMC for Lotka-Volterra (may take several minutes)...\n');
[status, output] = system(sprintf('uv run python "%s"', pythonScript), '-echo');
if status ~= 0
    error('Python script failed.\n\nOutput:\n%s', output);
end
fprintf('Python script finished successfully.\n\n');

%% ── 3. Load exported CSVs ───────────────────────────────────────────────
obs      = readtable(fullfile(resultsDir, 'observed_data_out.csv'));
meanTraj = readtable(fullfile(resultsDir, 'mean_trajectory.csv'));
post     = readtable(fullfile(resultsDir, 'posterior_samples.csv'));
preyMat  = readmatrix(fullfile(resultsDir, 'prey_trajectories.csv'),     'NumHeaderLines', 1);
predMat  = readmatrix(fullfile(resultsDir, 'predator_trajectories.csv'), 'NumHeaderLines', 1);

t              = meanTraj.t;
prey_obs       = obs.prey_observed;
prey_mean      = meanTraj.prey;
predator_mean  = meanTraj.predator;

param_names = {'alpha','beta','delta','gamma'};
param_samps = {post.alpha, post.beta, post.delta, post.gamma};
param_colors = {[0.12 0.47 0.71], [1.00 0.50 0.05], [0.17 0.63 0.17], [0.84 0.15 0.16]};

%% ── 4. Plot: Posterior predictive ──────────────────────────────────────
figure('Name','LV Posterior Predictive','Color','w','Position',[100 100 900 420]);
hold on;
for k = 1:size(preyMat, 2)
    plot(t, preyMat(:,k), 'Color', [0.12 0.47 0.71 0.08]);
    plot(t, predMat(:,k), 'Color', [1.00 0.50 0.05 0.08]);
end
h1 = plot(t, prey_mean,     'Color',[0.12 0.47 0.71], 'LineWidth',2.5, 'DisplayName','Mean prey');
h2 = plot(t, predator_mean, 'Color',[1.00 0.50 0.05], 'LineWidth',2.5, 'DisplayName','Mean predator (unobserved)');
h3 = scatter(t, prey_obs, 40, [0.12 0.47 0.71], 'o', 'filled', ...
             'MarkerEdgeColor','k', 'DisplayName','Prey (observed)');
xlabel('Time'); ylabel('Population');
title('Lotka-Volterra — Posterior Predictive (ABC-SMC)');
legend([h1 h2 h3], 'Location','best'); grid on; hold off;
exportgraphics(gcf, fullfile(resultsDir, 'matlab_lv_predictive.pdf'), 'ContentType','vector');

%% ── 5. Plot: Posterior marginals ────────────────────────────────────────
figure('Name','LV Posterior Marginals','Color','w','Position',[100 100 1100 350]);
for p = 1:4
    samp = param_samps{p};
    subplot(1,4,p);
    histogram(samp, 40, 'FaceColor', param_colors{p}, 'EdgeColor','w', 'Normalization','pdf');
    xline(mean(samp),    'r--', 'LineWidth',1.8, 'Label', sprintf('mean=%.3g', mean(samp)));
    xline(true_vals(p),  'k-',  'LineWidth',1.5, 'Label', sprintf('true=%.3g', true_vals(p)));
    xlabel(param_names{p}); ylabel('Density');
    title(['Posterior: ' param_names{p}]); grid on;
end
sgtitle('Posterior Marginals — Lotka-Volterra (ABC-SMC)');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_lv_marginals.pdf'), 'ContentType','vector');

%% ── 6. Plot: Trace-style ────────────────────────────────────────────────
figure('Name','LV Sample Traces','Color','w','Position',[100 100 1000 600]);
for p = 1:4
    subplot(4,1,p);
    plot(param_samps{p}, 'Color', param_colors{p}, 'LineWidth', 0.8);
    ylabel(param_names{p}); xlabel('Sample index');
    title(['Trace — ' param_names{p}]); grid on;
end
sgtitle('Posterior Samples — Lotka-Volterra');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_lv_trace.pdf'), 'ContentType','vector');

%% ── 7. Summary ──────────────────────────────────────────────────────────
fprintf('\n%-8s  %12s  %12s  %10s\n', 'Param', 'True', 'Post.mean', 'RelErr%%');
fprintf('%s\n', repmat('-',1,46));
for p = 1:4
    m = mean(param_samps{p});
    fprintf('%-8s  %12.4g  %12.4g  %9.2f%%\n', ...
            param_names{p}, true_vals(p), m, 100*abs(m-true_vals(p))/true_vals(p));
end
fprintf('\nAll MATLAB plots saved to "%s".\n', resultsDir);
