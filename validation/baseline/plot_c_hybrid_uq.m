function plot_c_hybrid_uq(results_txt, data_txt, out_stem, alp)
%PLOT_C_HYBRID_UQ Render a C cuqdyn-results.txt exactly like plot_hybrid_uq.
%
%   plot_c_hybrid_uq('c_nfkb_seed1_results.txt', ...
%                    '../../example-files/nfkb_paper_data.txt', ...
%                    'c_nfkb_seed1_hybrid_uq_plot', 0.05)
%
% Same grid (min(3,nstates) columns), same default colour cycle, same band /
% best-fit / data-marker styling and legends as CUQDyn1_Plus/src/
% plot_hybrid_uq.m, but fed from the C output. Because the drawing code is
% MATLAB in both cases, the MATLAB and C figures are comparable panel by
% panel with no cosmetic differences.
%
% data_txt is the C-format data file ("m n" header, time + one column per
% state, NaN = hidden); it provides the data markers and the observability
% pattern. Lower bands are clamped at 0 like plot_hybrid_uq.

if nargin < 4, alp = 0.05; end

res = read_c_results(results_txt);
raw = readmatrix(data_txt, 'FileType', 'text', 'NumHeaderLines', 1);
times = raw(:, 1);
data = raw(:, 2:end);
nstates = size(data, 2);
observed_idx = find(~any(isnan(data(2:end, :)), 1));

coverage_pct = 100 * (1 - 2 * alp);
num_cols = min(3, nstates);
num_rows = ceil(nstates / num_cols);
fig = figure('Color', 'w', 'Position', [100 100 420*num_cols+80 330*num_rows+80]);
def_colors = get(groot, 'DefaultAxesColorOrder');

for j = 1:nstates
    subplot(num_rows, num_cols, j);
    hold on; grid on;
    c = def_colors(mod(j-1, size(def_colors, 1)) + 1, :);

    ql = max(res.Q_low(:, j), 0);
    qu = res.Q_up(:, j);
    fill([times; flipud(times)], [ql; flipud(qu)], c, ...
        'FaceAlpha', 0.25, 'EdgeColor', 'none', ...
        'DisplayName', sprintf('%g%% PI', coverage_pct));

    if ismember(j, observed_idx)
        plot(times, res.MediaTot(:, j), '-', 'Color', c, 'LineWidth', 2, ...
            'DisplayName', 'best fit');
        plot(times, data(:, j), 'o', 'MarkerSize', 5, ...
            'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'w', ...
            'LineStyle', 'none', 'DisplayName', 'data');
        kind = 'observed';
    else
        plot(times, res.MediaTot(:, j), '--', 'Color', c, 'LineWidth', 2, ...
            'DisplayName', 'best fit');
        kind = 'unobserved';
    end

    title(sprintf('State %d (%s) - %g%% PI', j, kind, coverage_pct));
    xlabel('Time'); ylabel('Value');
    legend('Location', 'best');
end

sgtitle('CUQDyn-C - prediction bands', 'FontWeight', 'bold');
exportgraphics(fig, [out_stem '.png'], 'Resolution', 150);
savefig(fig, [out_stem '.fig']);
close(fig);
fprintf('Written %s.png\n', out_stem);
end

function s = read_c_results(path)
txt = fileread(path);
s = struct();
for name = {'Q_low', 'Q_up', 'MediaTot'}
    n = name{1};
    tok = regexp(txt, ['\[' n '\]\s*\n(\d+) (\d+)\s*\n'], 'tokens', 'once');
    if isempty(tok), error('plot_c_hybrid_uq:parse', 'section %s not found', n); end
    rows = str2double(tok{1}); cols = str2double(tok{2});
    pos = regexp(txt, ['\[' n '\]\s*\n\d+ \d+\s*\n'], 'end', 'once');
    vals = sscanf(txt(pos+1:end), '%f', rows * cols);
    s.(n) = reshape(vals, cols, rows).';
end
end
