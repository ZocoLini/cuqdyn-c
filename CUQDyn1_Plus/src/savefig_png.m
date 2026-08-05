function savefig_png(fig, base_path, res)
% SAVEFIG_PNG  Save a figure as .fig, .png, .pdf, and .eps.
%
%   savefig_png(fig, base_path)       saves at 150 DPI
%   savefig_png(fig, base_path, res)  saves at res DPI
%
%   base_path must be given WITHOUT extension; the function appends
%   '.fig', '.png', '.pdf', and '.eps' automatically.
%
%   Uses exportgraphics (R2020a+) for PNG output instead of print/saveas,
%   avoiding the SubplotListenersManager crash that occurs with sgtitle +
%   linkaxes figures in interactive MATLAB desktop sessions.
%
%   Before exporting, the figure is forced to a light (manuscript-ready)
%   appearance: white figure and axes backgrounds with black axis lines and
%   text. This makes saved figures render on white regardless of the MATLAB
%   UI theme active when they were created. Without it, plots produced under a
%   dark or "System" theme are saved with a black axes background. All toolbox
%   figures are intended for light manuscript output, so this is applied by
%   default; the modified appearance is also written into the saved .fig.

if nargin < 3 || isempty(res)
    res = 150;
end
base_path = char(base_path);   % accept both string and char inputs

% Enforce a light appearance so output does not depend on the active UI theme.
force_light_appearance(fig);

% exportgraphics must come before savefig: savefig's serialisation can
% invalidate sgtitle/linkaxes handles, causing exportgraphics to fail.
exportgraphics(fig, [base_path '.png'], 'Resolution', res);
try
    exportgraphics(fig, [base_path '.pdf'], 'ContentType', 'vector');
catch ME
    warning('savefig_png:PDFExportFailed', ...
        'Could not export %s.pdf: %s', base_path, ME.message);
end
try
    print(fig, [base_path '.eps'], '-depsc', '-painters');
catch ME
    warning('savefig_png:EPSExportFailed', ...
        'Could not export %s.eps: %s', base_path, ME.message);
end
savefig(fig, [base_path '.fig']);
end

% -------------------------------------------------------------------------
function force_light_appearance(fig)
% Set white figure/axes backgrounds and black axis lines/text so figures are
% saved for light (manuscript) output regardless of the active theme.
try
    try
        theme(fig, 'light');   % R2025a+ figure theming, when available
    catch
    end
    set(fig, 'Color', 'w');
    ax = findall(fig, 'Type', 'axes');
    if ~isempty(ax)
        set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'ZColor', 'k', ...
            'GridColor', [0.15 0.15 0.15], 'MinorGridColor', [0.30 0.30 0.30]);
    end
    set(findall(fig, 'Type', 'colorbar'), 'Color', 'k');
    lg = findall(fig, 'Type', 'legend');
    if ~isempty(lg)
        set(lg, 'Color', 'w', 'TextColor', 'k', 'EdgeColor', [0.5 0.5 0.5]);
    end
    set(findall(fig, 'Type', 'text'), 'Color', 'k');
catch ME
    warning('savefig_png:LightAppearanceFailed', ...
        'Could not enforce light figure appearance: %s', ME.message);
end
end
