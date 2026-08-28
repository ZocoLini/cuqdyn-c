function plot_matlab_vs_c(model)
%PLOT_MATLAB_VS_C One figure per model: MATLAB bands (left) vs C bands (right).
%
%   plot_matlab_vs_c('lv2')   ->  compare_lv2_matlab_vs_c.png (+ .fig)
%
% Both halves are drawn by this same function with the plot_hybrid_uq styling,
% so any visual difference between the two sides is in the data, never in the
% plotting. MATLAB bands come from the layer-3 export
% (matlab/<model>/layer3/); C bands from the seed-1 reference run
% (c_<model>_seed1_results.txt). Lower bands are clamped at 0, like
% plot_hybrid_uq.

here = fileparts(mfilename('fullpath'));
mdir = fullfile(here, 'matlab', model);

% --- MATLAB side (layer-3 export) ---
times = read_m(fullfile(mdir, 'times.txt'));
obs_idx = read_m(fullfile(mdir, 'observed_idx.txt'));          % 1-based
ql_m = read_m(fullfile(mdir, 'layer3', 'q_low.txt'));
qu_m = read_m(fullfile(mdir, 'layer3', 'q_up.txt'));
fit_m = read_m(fullfile(mdir, 'layer3', 'media_tot.txt'));
obs_data = read_m(fullfile(mdir, 'layer3', 'observed_data.txt'));
nstates = size(fit_m, 2);

% --- C side (seed-1 reference results) ---
cres = read_c_results(fullfile(here, sprintf('c_%s_seed1_results.txt', model)));
ql_c = cres.Q_low; qu_c = cres.Q_up; fit_c = cres.MediaTot;

alp = read_kv(fullfile(mdir, 'meta.txt'), 'alp');
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

out = fullfile(here, sprintf('compare_%s_matlab_vs_c', model));
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

function M = read_m(path)
fid = fopen(path, 'r');
if fid < 0, error('plot_matlab_vs_c:io', 'cannot read %s', path); end
dims = fscanf(fid, '%d', 2);
M = fscanf(fid, '%f', [dims(2), dims(1)]).';
fclose(fid);
end

function v = read_kv(path, key)
v = NaN;
fid = fopen(path, 'r');
while true
    line = fgetl(fid);
    if ~ischar(line), break; end
    parts = strsplit(strtrim(line));
    if numel(parts) >= 2 && strcmp(parts{1}, key)
        v = str2double(parts{2});
        break;
    end
end
fclose(fid);
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
