%% run_bayes_sir.m
% Calls the Python ABC-SMC script for the SIR epidemic model and plots results.
%
% Model: dS/dt = -beta*S*I   [UNOBSERVED]
%        dI/dt =  beta*S*I - gamma*I  [OBSERVED]
%        dR/dt =  gamma*I   [UNOBSERVED]
%
% Inferred parameters: beta, gamma
% Data: both methods use the same synthetic dataset in
%       EXAMPLES/SIR/data/sir_data.csv.
%
% Run this script from within the pymc_matlab/ directory.

%% ── 0. Pre-flight: verify shared data CSV exists ────────────────────────
dataCSV = fullfile('..', 'EXAMPLES', 'SIR', 'data', 'sir_data.csv');
if ~isfile(dataCSV)
    error(['SIR data CSV not found:\n  %s\n' ...
           'Regenerate it with EXAMPLES/SIR/data_generation/generateSyntheticData_SIR.m.'], dataCSV);
end

%% ── 1. Configuration ────────────────────────────────────────────────────
pythonScript = 'sir_pymc.py';
resultsDir   = fullfile('results', 'sir');
true_vals    = [0.002, 0.5];    % beta, gamma
param_names  = {'beta','gamma'};

%% ── 2. Run Python via uv ────────────────────────────────────────────────
fprintf('Running Python ABC-SMC for SIR (may take several minutes)...\n');
[status, output] = system(sprintf('uv run python "%s"', pythonScript), '-echo');
if status ~= 0
    error('Python script failed.\n\nOutput:\n%s', output);
end
fprintf('Python script finished successfully.\n\n');

%% ── 3. Load exported CSVs ───────────────────────────────────────────────
obs      = readtable(fullfile(resultsDir, 'observed_data_out.csv'));
meanTraj = readtable(fullfile(resultsDir, 'mean_trajectory.csv'));
post     = readtable(fullfile(resultsDir, 'posterior_samples.csv'));
sMat     = readmatrix(fullfile(resultsDir, 'susceptible_trajectories.csv'), 'NumHeaderLines', 1);
iMat     = readmatrix(fullfile(resultsDir, 'infected_trajectories.csv'),    'NumHeaderLines', 1);
rMat     = readmatrix(fullfile(resultsDir, 'recovered_trajectories.csv'),   'NumHeaderLines', 1);

t            = meanTraj.t;
inf_obs      = obs.infected_observed;
beta_samp    = post.beta;
gamma_samp   = post.gamma;

state_labels = {'Susceptible (unobserved)', 'Infected (observed)', 'Recovered (unobserved)'};
state_colors = {[0.84 0.15 0.16], [0.12 0.47 0.71], [0.17 0.63 0.17]};
traj_mats    = {sMat, iMat, rMat};
mean_cols    = {'susceptible', 'infected', 'recovered'};

%% ── 4. Plot: Posterior predictive ───────────────────────────────────────
figure('Name','SIR Posterior Predictive','Color','w','Position',[50 50 1200 420]);
for j = 1:3
    subplot(1,3,j); hold on;
    col  = state_colors{j};
    traj = traj_mats{j};
    for k = 1:size(traj,2)
        plot(t, traj(:,k), 'Color', [col 0.08]);
    end
    plot(t, meanTraj.(mean_cols{j}), 'Color', col, 'LineWidth', 2.5, 'DisplayName','Mean');
    if j == 2
        scatter(t, inf_obs, 30, col, 'o', 'filled', ...
                'MarkerEdgeColor','k', 'DisplayName','Observed');
        legend('Location','best','FontSize',9);
    end
    xlabel('Time (days)'); ylabel('Population');
    title(state_labels{j}); grid on; hold off;
end
sgtitle('SIR model — Posterior Predictive (ABC-SMC)');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_sir_predictive.pdf'), 'ContentType','vector');

%% ── 5. Plot: Posterior marginals ────────────────────────────────────────
figure('Name','SIR Posterior Marginals','Color','w','Position',[100 100 700 350]);
for p = 1:2
    col  = state_colors{p};
    samp = post.(param_names{p});
    subplot(1,2,p);
    histogram(samp, 40, 'FaceColor', col, 'EdgeColor','w', 'Normalization','pdf');
    xline(mean(samp),   'r--', 'LineWidth',1.8, 'Label', sprintf('mean=%.4g', mean(samp)));
    xline(true_vals(p), 'k-',  'LineWidth',1.5, 'Label', sprintf('true=%.4g', true_vals(p)));
    xlabel(param_names{p}); ylabel('Density');
    title(['Posterior: ' param_names{p}]); grid on;
end
sgtitle('Posterior Marginals — SIR (ABC-SMC)');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_sir_marginals.pdf'), 'ContentType','vector');

%% ── 6. Plot: Trace-style ────────────────────────────────────────────────
figure('Name','SIR Sample Traces','Color','w','Position',[100 100 900 450]);
subplot(2,1,1);
plot(beta_samp,  'Color', state_colors{1}, 'LineWidth', 0.8);
ylabel('beta'); xlabel('Sample index'); title('Trace — beta'); grid on;

subplot(2,1,2);
plot(gamma_samp, 'Color', state_colors{2}, 'LineWidth', 0.8);
ylabel('gamma'); xlabel('Sample index'); title('Trace — gamma'); grid on;

sgtitle('Posterior Samples — SIR');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_sir_trace.pdf'), 'ContentType','vector');

%% ── 7. Summary ──────────────────────────────────────────────────────────
fprintf('\n%-8s  %12s  %12s  %10s\n', 'Param', 'True', 'Post.mean', 'RelErr%%');
fprintf('%s\n', repmat('-',1,47));
for p = 1:2
    m = mean(post.(param_names{p}));
    fprintf('%-8s  %12.4g  %12.4g  %9.2f%%\n', ...
            param_names{p}, true_vals(p), m, 100*abs(m-true_vals(p))/true_vals(p));
end
fprintf('\nAll MATLAB plots saved to "%s".\n', resultsDir);
