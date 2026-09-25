function plot_matlab_vs_c(model, c_results)
%PLOT_MATLAB_VS_C One figure per model: MATLAB bands (left) vs C bands (right).
%
%   plot_matlab_vs_c('lv2', 'results/layer6/lv2/c/seed_1/cuqdyn-results.txt')
%       ->  compare_lv2_matlab_vs_c.png (+ .fig) next to that file
%
% Both halves are drawn by this same function with the plot_hybrid_uq styling,
% so any visual difference between the two sides is in the data, never in the
% plotting. The MATLAB bands are the layer-4 sections of references/<model>.txt;
% the C bands come from any cuqdyn-results.txt, typically one layer-6 seed.
% Lower bands are clamped at 0, like plot_hybrid_uq.

if nargin < 2 || isempty(c_results)
    error('plot_matlab_vs_c:usage', 'plot_matlab_vs_c(model, path_to_cuqdyn_results_txt)');
end

here = fileparts(mfilename('fullpath'));
addpath(here);
ref = fullfile(here, '..', 'references', [model '.txt']);

% --- MATLAB side (layer-4 sections + problem context) ---
times = read_section_matrix(ref, 'times');
obs_idx = read_section_matrix(ref, 'observed_idx');       % 1-based
ql_m = read_section_matrix(ref, 'q_low');
qu_m = read_section_matrix(ref, 'q_up');
fit_m = read_section_matrix(ref, 'media_tot');
obs_data = read_section_matrix(ref, 'observed_data');
nstates = size(fit_m, 2);

% --- C side ---
cres = read_c_results(c_results);
ql_c = cres.Q_low; qu_c = cres.Q_up; fit_c = cres.MediaTot;

alp = str2double(read_section_kv(ref, 'meta', 'alp'));
coverage_pct = 100 * (1 - 2 * alp);

ncs = min(3, nstates);            % state-columns per side
nrows = ceil(nstates / ncs);
ncols = 2 * ncs;                  % left half MATLAB, right half C

fig = figure('Color', 'w', 'Position', [50 50 380*ncols+100 300*nrows+100]);
def_colors = get(groot, 'DefaultAxesColorOrder');

for j = 1:nstates
    is_obs = ismember(j, obs_idx);
    c = def_colors(mod(j-1, size(def_colors,1)) + 1, :);
    r = ceil(j / ncs);
    col = mod(j-1, ncs) + 1;

    % MATLAB panel (left half)
    subplot(nrows, ncols, (r-1)*ncols + col);
    draw_panel(times, ql_m(:,j), qu_m(:,j), fit_m(:,j), is_obs, c, ...
        obs_data, obs_idx, j, sprintf('State %d - MATLAB', j), coverage_pct);

    % C panel (right half)
    subplot(nrows, ncols, (r-1)*ncols + ncs + col);
    draw_panel(times, ql_c(:,j), qu_c(:,j), fit_c(:,j), is_obs, c, ...
        obs_data, obs_idx, j, sprintf('State %d - C', j), coverage_pct);
end

sgtitle(sprintf('%s - %g%% prediction bands: MATLAB (left) vs C (right)', ...
    upper(model), coverage_pct), 'FontWeight', 'bold');

out = fullfile(fileparts(c_results), sprintf('compare_%s_matlab_vs_c', model));
exportgraphics(fig, [out '.png'], 'Resolution', 150);
savefig(fig, [out '.fig']);
close(fig);
fprintf('Written %s.png\n', out);
end

function draw_panel(t, ql, qu, fit, is_obs, c, obs_data, obs_idx, j, titlestr, cov)
hold on; grid on;
ql = max(ql, 0);                                  % clamp like plot_hybrid_uq
fill([t; flipud(t)], [ql; flipud(qu)], c, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
if is_obs
    plot(t, fit, '-', 'Color', c, 'LineWidth', 1.8);
    k = find(obs_idx == j);
    plot(t, obs_data(:, k), 'o', 'MarkerSize', 4.5, ...
        'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'w');
    kind = 'observed';
else
    plot(t, fit, '--', 'Color', c, 'LineWidth', 1.8);
    kind = 'unobserved';
end
title(sprintf('%s (%s) - %g%% PI', titlestr, kind, cov), 'FontSize', 9);
xlabel('Time'); ylabel('Value');
end

function s = read_c_results(path)
% Parse the labelled sections of cuqdyn-results.txt into a struct.
txt = fileread(path);
s = struct();
for name = {'Q_low', 'Q_up', 'MediaTot'}
    n = name{1};
    tok = regexp(txt, ['\[' n '\]\s*\n(\d+) (\d+)\s*\n'], 'tokens', 'once');
    if isempty(tok), error('plot_matlab_vs_c:parse', 'section %s not found', n); end
    rows = str2double(tok{1}); cols = str2double(tok{2});
    pos = regexp(txt, ['\[' n '\]\s*\n\d+ \d+\s*\n'], 'end', 'once');
    vals = sscanf(txt(pos+1:end), '%f', rows * cols);
    s.(n) = reshape(vals, cols, rows).';
end
end
