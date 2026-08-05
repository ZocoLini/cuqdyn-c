% --- Paths ---
repoRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(repoRoot, 'src'));
addpath(genpath(fullfile(repoRoot, 'EXAMPLES')));

% MEIGO64 is required by the example optimisation scripts. Set MEIGO64_PATH
% or place MEIGO64-master next to this file to add it automatically.
meigoPath = getenv('MEIGO64_PATH');
if strlength(meigoPath) == 0
    meigoPath = fullfile(repoRoot, 'MEIGO64-master');
end

if isfolder(meigoPath)
    addpath(genpath(meigoPath));
else
    warning('CUQDyn1_Plus:MEIGONotFound', ...
        'MEIGO64 not found. Set MEIGO64_PATH before running optimisation examples.');
end
