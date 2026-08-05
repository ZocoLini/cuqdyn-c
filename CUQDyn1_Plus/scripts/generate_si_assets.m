function generate_si_assets(repoRoot)
%GENERATE_SI_ASSETS  Build bespoke figures used by the Supplementary Information.
%
%   generate_si_assets()           % auto-detect repo root from this file
%   generate_si_assets(repoRoot)   % explicit repo root
%
%   Currently produces scripts/si_assets/lc3_k1k2_nonidentif.{png,pdf,eps,fig}:
%   an illustration of the LinearCascade3 upstream (k1<->k2) non-identifiability
%   that assemble_si.py embeds in Part IV of the SI. The wrong-branch parameters
%   are taken from a 0%-coverage replicate of the latest LinearCascade3
%   shared-fit SBC run, so the figure reflects the actual calibration.

if nargin < 1 || isempty(repoRoot)
    repoRoot = fileparts(fileparts(mfilename('fullpath')));  % scripts/ -> repo
end
addpath(genpath(repoRoot));
assetsDir = fullfile(repoRoot, 'scripts', 'si_assets');
if ~exist(assetsDir, 'dir'); mkdir(assetsDir); end

% locate the latest LinearCascade3 shared-fit SBC workspace
d = dir(fullfile(repoRoot,'EXAMPLES','LinearCascade', ...
    'SBC_Results_LinearCascade3_sharedfit_*'));
d = d([d.isdir]);
if isempty(d)
    warning('generate_si_assets:NoSBC', 'No LinearCascade3 SBC folder found; skipping.');
    return;
end
[~, ix] = sort({d.name}); d = d(ix);
sbcDir = fullfile(d(end).folder, d(end).name);
W = load(fullfile(sbcDir, 'SBC_LinearCascade3_sharedfit_workspace.mat'));

covr = squeeze(mean(mean(W.covered_fim, 2), 3));   % per-replicate coverage
badrep = find(covr <= 0.10, 1, 'first');           % a catastrophic replicate
if isempty(badrep)
    warning('generate_si_assets:NoBadRep', 'No low-coverage replicate; skipping figure.');
    return;
end
kt = [0.45, 0.16, 0.055];              % true parameters
kb = W.params_fit(badrep, :);          % fitted wrong-branch parameters
dyn = @prob_mod_dynamics_LinearCascade3; ic = [10, 0, 0]; tp = (0:0.5:35)';
oo = odeset('RelTol', 1e-9, 'AbsTol', 1e-11);
[~, Xt] = ode15s(@(t,y) dyn(t,y,kt), tp, ic, oo);
[~, Xb] = ode15s(@(t,y) dyn(t,y,kb), tp, ic, oo);
x3rmse = sqrt(mean((Xb(:,3) - Xt(:,3)).^2));
dfile = fullfile(sbcDir, 'tmp_data', sprintf('linear_cascade3_sbc_rep%03d.csv', badrep));
if exist(dfile, 'file'); data = readmatrix(dfile); else; data = []; end

f = figure('Color', 'w', 'Position', [100 100 1150 340]);
lbl = {'Hidden x_1', 'Hidden x_2', 'Observed x_3'};
for j = 1:3
    ax = subplot(1,3,j); hold(ax,'on'); grid(ax,'on'); box(ax,'on');
    plot(tp, Xt(:,j), '-',  'Color',[0.10 0.45 0.80], 'LineWidth',2.2, 'DisplayName','true parameters');
    plot(tp, Xb(:,j), '--', 'Color',[0.85 0.30 0.10], 'LineWidth',2.2, 'DisplayName','wrong-branch fit');
    if j == 3 && ~isempty(data)
        plot(data(2:end,1), data(2:end,4), 'ko','MarkerSize',4, ...
            'MarkerFaceColor',[.4 .4 .4], 'DisplayName','noisy data');
        legend(ax,'Location','northeast','FontSize',9);
    end
    xlabel(ax,'time'); ylabel(ax,'value'); title(ax, lbl{j}, 'FontWeight','bold');
end
sgtitle(sprintf(['LinearCascade3 non-identifiability: wrong-branch fit ' ...
    'reproduces observed x_3 (RMSE %.3f) but misses hidden x_1, x_2'], x3rmse), ...
    'FontWeight','bold');
savefig_png(f, fullfile(assetsDir, 'lc3_k1k2_nonidentif'));
close(f);
fprintf('generate_si_assets: wrote %s (bad rep %d, x3 RMSE %.3f)\n', ...
    fullfile(assetsDir,'lc3_k1k2_nonidentif.png'), badrep, x3rmse);
end
