%% run_bayes_ap.m
% Calls the Python ABC-SMC script for Alpha-Pinene and plots results.
%
% Model: 5-state isomerisation network.
%   dy1 = -(p1+p2)*y1
%   dy2 = p1*y1
%   dy3 = p2*y1 - (p3+p4)*y3 + p5*y5
%   dy4 = p3*y3
%   dy5 = p4*y3 - p5*y5       [UNOBSERVED after t=0]
%
% States y1-y4 observed; y5 (delta-3-carene) unobserved.
% Inferred parameters: p1 ... p5
% Data: ../EXAMPLES/AP/data/AP_measurementData_1_4.csv
%
% Run this script from within the pymc_matlab/ directory.

%% -- 0. Pre-flight: verify shared data CSV exists -------------------------
dataCSV = fullfile('..', 'EXAMPLES', 'AP', 'data', ...
    'AP_measurementData_1_4.csv');
if ~isfile(dataCSV)
    error(['AP data CSV not found:\n  %s\n' ...
           'Regenerate it with EXAMPLES/AP/data_generation/generateSyntheticData_AP.m.'], dataCSV);
end

%% ── 1. Configuration ────────────────────────────────────────────────────
pythonScript = 'ap_pymc.py';
resultsDir   = fullfile('results', 'ap');
true_vals    = [5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05];
param_names  = {'p1','p2','p3','p4','p5'};
state_names  = {'y1','y2','y3','y4','y5 (unobs)'};

%% ── 2. Run Python via uv ────────────────────────────────────────────────
fprintf('Running Python ABC-SMC for Alpha-Pinene (may take several minutes)...\n');
[status, output] = system(sprintf('uv run python "%s"', pythonScript), '-echo');
if status ~= 0
    error('Python script failed.\n\nOutput:\n%s', output);
end
fprintf('Python script finished successfully.\n\n');

%% ── 3. Load exported CSVs ───────────────────────────────────────────────
obs      = readtable(fullfile(resultsDir, 'observed_data_out.csv'));
meanTraj = readtable(fullfile(resultsDir, 'mean_trajectory.csv'));
post     = readtable(fullfile(resultsDir, 'posterior_samples.csv'));

t = meanTraj.t;

% Trajectory matrices: one per state, each [n_times x 75]
trajMats = cell(1,5);
state_file_names = {'y1','y2','y3','y4','y5'};
for j = 1:5
    fname = fullfile(resultsDir, [state_file_names{j} '_trajectories.csv']);
    trajMats{j} = readmatrix(fname, 'NumHeaderLines', 1);
end

param_samps = {post.p1, post.p2, post.p3, post.p4, post.p5};
state_colors = {[0.12 0.47 0.71], [1.00 0.50 0.05], [0.17 0.63 0.17], ...
                [0.84 0.15 0.16], [0.58 0.40 0.74]};

%% ── 4. Plot: Posterior predictive (all 5 states) ────────────────────────
figure('Name','AP Posterior Predictive','Color','w','Position',[50 50 1400 400]);
for j = 1:5
    subplot(1,5,j); hold on;
    col = state_colors{j};
    traj = trajMats{j};
    for k = 1:size(traj,2)
        plot(t, traj(:,k), 'Color', [col 0.08]);
    end
    plot(t, meanTraj.(sprintf('y%d',j)), 'Color', col, 'LineWidth', 2.5, ...
         'DisplayName', 'Mean');
    if j <= 4
        scatter(t, obs.(sprintf('y%d',j)), 30, col, 'o', 'filled', ...
                'MarkerEdgeColor','k', 'DisplayName','Observed');
        legend('Location','best','FontSize',7);
    end
    xlabel('Time'); ylabel('Concentration');
    title(state_names{j}); grid on; hold off;
end
sgtitle('Alpha-Pinene — Posterior Predictive (ABC-SMC)');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_ap_predictive.pdf'), 'ContentType','vector');

%% ── 5. Plot: Posterior marginals ────────────────────────────────────────
figure('Name','AP Posterior Marginals','Color','w','Position',[100 100 1300 350]);
for p = 1:5
    samp = param_samps{p};
    subplot(1,5,p);
    histogram(samp, 40, 'FaceColor', state_colors{p}, 'EdgeColor','w', 'Normalization','pdf');
    xline(mean(samp),   'r--', 'LineWidth',1.8, 'Label', sprintf('mean=%.3g', mean(samp)));
    xline(true_vals(p), 'k-',  'LineWidth',1.5, 'Label', sprintf('true=%.3g', true_vals(p)));
    xlabel(param_names{p}); ylabel('Density');
    title(['Posterior: ' param_names{p}]); grid on;
end
sgtitle('Posterior Marginals — Alpha-Pinene (ABC-SMC)');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_ap_marginals.pdf'), 'ContentType','vector');

%% ── 6. Plot: Trace-style ────────────────────────────────────────────────
figure('Name','AP Sample Traces','Color','w','Position',[100 100 1000 700]);
for p = 1:5
    subplot(5,1,p);
    plot(param_samps{p}, 'Color', state_colors{p}, 'LineWidth', 0.8);
    ylabel(param_names{p}); xlabel('Sample index');
    title(['Trace — ' param_names{p}]); grid on;
end
sgtitle('Posterior Samples — Alpha-Pinene');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_ap_trace.pdf'), 'ContentType','vector');

%% ── 7. Summary ──────────────────────────────────────────────────────────
fprintf('\n%-6s  %12s  %12s  %10s\n', 'Param', 'True', 'Post.mean', 'RelErr%%');
fprintf('%s\n', repmat('-',1,45));
for p = 1:5
    m = mean(param_samps{p});
    fprintf('%-6s  %12.4g  %12.4g  %9.2f%%\n', ...
            param_names{p}, true_vals(p), m, 100*abs(m-true_vals(p))/true_vals(p));
end
fprintf('\nAll MATLAB plots saved to "%s".\n', resultsDir);
