%% run_bayes_nfkb.m
% Calls the Python ABC-SMC script for the NF-kB model and plots results.
%
% Model: 15-state NF-kB signalling network (see prob_mod_dynamics_NFKB.m).
%   Observed (10): y1, y2, y3, y5, y7, y9, y11, y12, y13, y15
%   Unobserved (5): y4, y6, y8, y10, y14
%   Parameters: 29  (p1 ... p29)
%
% Data: ../EXAMPLES/NFKB/data/NFKB_synthetic_data_5n_36st_partobs10.csv
%       (5% noise, 36 sampling times)
%
% Run this script from within the pymc_matlab/ directory.

%% -- 0. Pre-flight: verify shared data CSV exists --------------------------
dataCSV = fullfile('..', 'EXAMPLES', 'NFKB', 'data', ...
    'NFKB_synthetic_data_5n_36st_partobs10.csv');
if ~isfile(dataCSV)
    error(['NFKB data CSV not found:\n  %s\n' ...
           'Regenerate it with EXAMPLES/NFKB/data_generation/generateSyntheticData_NFKB.m.'], dataCSV);
end

%% -- 1. Configuration -------------------------------------------------------
pythonScript = 'nfkb_pymc.py';
resultsDir   = fullfile('results', 'nfkb');

true_vals = [0.5    0.2      0.1      1.0     0.1     ...
             5e-7   0.0001   0.0004   0.5     0.0001  ...
             0.00002 5e-7    0.0001   0.0004  0.5     ...
             0.0003 0.0025   0.1      0.0015  0.000025 ...
             0.000125 5.0    0.0025   0.01    0.001   ...
             0.0005 5e-7     0.0001   0.0004];

param_names = {'p1','p2','p3','p4','p5','p6','p7','p8','p9','p10', ...
               'p11','p12','p13','p14','p15','p16','p17','p18','p19','p20', ...
               'p21','p22','p23','p24','p25','p26','p27','p28','p29'};

state_names = {'y1 (obs)', 'y2 (obs)', 'y3 (obs)', 'y4',        'y5 (obs)', ...
               'y6',       'y7 (obs)', 'y8',        'y9 (obs)', 'y10',       ...
               'y11 (obs)','y12 (obs)','y13 (obs)', 'y14',       'y15 (obs)'};

obs_idx = [1 2 3 5 7 9 11 12 13 15];   % 1-based MATLAB indices of observed states

%% -- 2. Run Python via uv ---------------------------------------------------
fprintf('Running Python ABC-SMC for NF-kB (expect 30-60 min for 29 params)...\n');
[status, output] = system(sprintf('uv run python "%s"', pythonScript), '-echo');
if status ~= 0
    error('Python script failed.\n\nOutput:\n%s', output);
end
fprintf('Python script finished successfully.\n\n');

%% -- 3. Load exported CSVs --------------------------------------------------
obs      = readtable(fullfile(resultsDir, 'observed_data_out.csv'));
meanTraj = readtable(fullfile(resultsDir, 'mean_trajectory.csv'));
post     = readtable(fullfile(resultsDir, 'posterior_samples.csv'));

t = meanTraj.t;

% Per-state trajectory matrices [n_times x 75 samples]
trajMats = cell(1, 15);
for j = 1:15
    trajMats{j} = readmatrix(fullfile(resultsDir, sprintf('y%d_trajectories.csv', j)), ...
                             'NumHeaderLines', 1);
end

% Posterior sample vectors
param_samps = cell(1, 29);
for k = 1:29
    param_samps{k} = post.(param_names{k});
end

%% -- 4. Plot: Posterior predictive (all 15 states, 3x5 grid) ----------------
colors15 = lines(15);
figure('Name','NFKB Posterior Predictive','Color','w','Position',[50 50 1600 700]);
for j = 1:15
    subplot(3, 5, j);  hold on;
    col  = colors15(j, :);
    traj = trajMats{j};

    % Clip blow-up trajectories: keep only columns within 20x the mean range
    mean_col = meanTraj.(sprintf('y%d', j));
    yref     = max(abs(mean_col)) * 20;
    keep     = all(abs(traj) <= yref + eps, 1);
    traj     = traj(:, keep);

    % Ensemble trajectories — excluded from legend
    for k = 1:size(traj, 2)
        plot(t, traj(:,k), 'Color', [col 0.07], 'LineWidth', 0.5, ...
             'HandleVisibility', 'off');
    end

    % Mean trajectory
    h_mean = plot(t, mean_col, 'Color', col, 'LineWidth', 2.5);

    if ismember(j, obs_idx)
        obs_col = sprintf('y%d', j);
        h_obs   = scatter(t, obs.(obs_col), 18, col, 'o', 'filled', ...
                          'MarkerEdgeColor', 'k', 'LineWidth', 0.4);
        legend([h_mean, h_obs], {'Mean', 'Obs'}, 'Location', 'best', 'FontSize', 6);
    else
        legend(h_mean, {'Mean'}, 'Location', 'best', 'FontSize', 6);
    end

    xlabel('t (s)', 'FontSize', 7);
    ylabel('conc.',  'FontSize', 7);
    title(state_names{j}, 'FontSize', 8);
    grid on;  hold off;
end
sgtitle('NF-kB — Posterior Predictive (ABC-SMC)');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_nfkb_predictive.pdf'), 'ContentType', 'vector');

%% -- 5. Plot: Posterior marginals (29 params, 5x6 grid) ---------------------
figure('Name','NFKB Posterior Marginals','Color','w','Position',[50 50 1600 1100]);
for k = 1:29
    subplot(5, 6, k);
    col  = colors15(mod(k-1, 15) + 1, :);
    samp = param_samps{k};
    histogram(samp, 35, 'FaceColor', col, 'EdgeColor', 'w', 'Normalization', 'pdf');
    xline(mean(samp),   'r--', 'LineWidth', 1.5, 'Label', sprintf('%.3g', mean(samp)));
    xline(true_vals(k), 'k-',  'LineWidth', 1.2, 'Label', sprintf('%.3g', true_vals(k)));
    xlabel(param_names{k}, 'FontSize', 7);
    title(param_names{k}, 'FontSize', 8);
    grid on;
end
subplot(5, 6, 30);  axis off;   % unused panel
sgtitle('NF-kB — Posterior Marginals (ABC-SMC)');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_nfkb_marginals.pdf'), 'ContentType', 'vector');

%% -- 6. Plot: Trace-style (29 params, 6x5 grid) -----------------------------
figure('Name','NFKB Sample Traces','Color','w','Position',[50 50 1400 950]);
for k = 1:29
    subplot(6, 5, k);
    col = colors15(mod(k-1, 15) + 1, :);
    plot(param_samps{k}, 'Color', col, 'LineWidth', 0.6);
    ylabel(param_names{k}, 'FontSize', 7);
    xlabel('Sample', 'FontSize', 6);
    title(param_names{k}, 'FontSize', 8);
    grid on;
end
% hide unused panels (positions 30)
for k = 30
    subplot(6, 5, k);  axis off;
end
sgtitle('NF-kB — Posterior Samples');
exportgraphics(gcf, fullfile(resultsDir, 'matlab_nfkb_trace.pdf'), 'ContentType', 'vector');

%% -- 7. Summary table --------------------------------------------------------
fprintf('\n%-6s  %12s  %12s  %10s\n', 'Param', 'True', 'Post.mean', 'RelErr%');
fprintf('%s\n', repmat('-', 1, 46));
for k = 1:29
    m = mean(param_samps{k});
    fprintf('%-6s  %12.4g  %12.4g  %9.2f%%\n', ...
            param_names{k}, true_vals(k), m, 100*abs(m - true_vals(k))/true_vals(k));
end
fprintf('\nAll MATLAB plots saved to "%s".\n', resultsDir);
