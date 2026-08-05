function plot_hybrid_uq(results, resultDir)
%PLOT_HYBRID_UQ Plot all-state CUQDyn prediction bands and fitted trajectory.
%
% plot_hybrid_uq(results, resultDir) creates hybrid_uq_plot.png and
% hybrid_uq_plot.fig in resultDir. It works with CUQDyn1_Plus,
% CUQDyn1_Plus_HybridCov, and result-like structs containing the standard
% fields.
%
% For each state:
%   shaded band  results.UQ_lower/results.UQ_upper
%   best fit     results.media_tot, solid for observed and dashed for hidden
%   markers      finite observed data points for observed states only
%
% The function clamps negative lower bands to zero for plotting because the
% built-in examples represent nonnegative populations/concentrations.

times          = results.times;
all_state_data = results.all_state_data; %#ok<NASGU>
observed_data  = results.observed_data;
observed_idx   = results.observed_idx;
media_tot      = results.media_tot;
UQ_lower       = results.UQ_lower;
UQ_upper       = results.UQ_upper;
nstates        = results.nstates;
alp            = results.alp;

coverage_pct  = 100 * (1 - 2 * alp);
num_cols   = min(3, nstates);
num_rows   = ceil(nstates / num_cols);
fig = figure('Color', 'w', 'Position', [100 100 420*num_cols+80 330*num_rows+80]);

def_colors = get(groot, 'DefaultAxesColorOrder');

for j = 1:nstates
    subplot(num_rows, num_cols, j);
    hold on; grid on;

    c = def_colors(mod(j-1, size(def_colors,1)) + 1, :);

    % Conformal PI band
    lo_outer = max(0, UQ_lower(:,j));
    hi_outer = UQ_upper(:,j);
    fill([times(:); flipud(times(:))], [lo_outer; flipud(hi_outer)], ...
         c, 'FaceAlpha', 0.25, 'EdgeColor', 'none', ...
         'DisplayName', sprintf('%.0f%% PI', coverage_pct));

    % Best-fit trajectory
    is_obs = ismember(j, observed_idx);
    if is_obs
        plot(times, media_tot(:,j), '-',  'Color', c, 'LineWidth', 2.5, ...
             'DisplayName', 'best fit');
    else
        plot(times, media_tot(:,j), '--', 'Color', c, 'LineWidth', 2.5, ...
             'DisplayName', 'best fit');
    end

    % Data markers for observed states
    if is_obs
        obs_col = find(observed_idx == j, 1);
        plot(times, observed_data(:, obs_col), 'o', ...
             'Color', c, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k', ...
             'MarkerSize', 6, 'DisplayName', 'data');
        title(sprintf('State %d (observed) - %.0f%% PI', j, coverage_pct), ...
              'FontSize', 11, 'FontWeight', 'bold');
    else
        title(sprintf('State %d (unobserved) - %.0f%% PI', j, coverage_pct), ...
              'FontSize', 11, 'FontWeight', 'bold');
    end

    xlabel('Time',  'FontSize', 10);
    ylabel('Value', 'FontSize', 10);
    legend('FontSize', 9, 'Location', 'best');
end

sgtitle('CUQDyn1\_Plus - prediction bands', ...
        'FontSize', 14, 'FontWeight', 'bold');

savefig_png(fig, fullfile(resultDir, 'hybrid_uq_plot'));
fprintf('Plot saved to %s\n', resultDir);

end
