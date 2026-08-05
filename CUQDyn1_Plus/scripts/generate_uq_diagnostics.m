function generate_uq_diagnostics(repoRoot)
%GENERATE_UQ_DIAGNOSTICS  Post-hoc UQ diagnostics for the main benchmark runs.
%
%   generate_uq_diagnostics()           % auto-detect repo root from this file
%   generate_uq_diagnostics(repoRoot)   % explicit repo root
%
%   run_all_examples does not call diagnose_uq_quality for the main LV/SIR/AP/
%   NF-kB runs, so those result folders lack uq_diagnostics.xlsx. The
%   Supplementary Information identifiability table (assemble_si.py) reads that
%   file, so without this helper that table is empty on a fresh evaluation.
%
%   This function finds the latest FIM and HybridCov result folder for each of
%   LV, SIR, AP and NF-kB, loads the saved results struct, and calls
%   diagnose_uq_quality to write uq_diagnostics.xlsx / .mat into each folder.
%   It does not re-fit or re-solve anything; it only inspects stored fields.
%   Parameter/state names come from define_problem_<Model>. Bounds are omitted
%   on purpose (the conditioning/weak-direction diagnostics do not need them,
%   and AP/NF-kB runs use widened bounds not stored in define_problem).
%
%   Safe to call unattended: per-folder failures are caught and reported, never
%   thrown, so wiring this into run_full_evaluation cannot abort the run.

if nargin < 1 || isempty(repoRoot)
    thisFile  = mfilename('fullpath');
    repoRoot  = fileparts(fileparts(thisFile));   % scripts/ -> repo root
end
EX = fullfile(repoRoot, 'EXAMPLES');

jobs = {
    'LV',   latest_dir(fullfile(EX,'LV',  'Results_LV2_CUQDyn1_Plus_*')),         @define_problem_LV
    'LV',   latest_dir(fullfile(EX,'LV',  'Results_LV2_HybridCov_*')),            @define_problem_LV
    'SIR',  latest_dir(fullfile(EX,'SIR', 'Results_SIR_CUQDyn1Plus_*')),          @define_problem_SIR
    'SIR',  latest_dir(fullfile(EX,'SIR', 'Results_SIR_HybridCov_*')),            @define_problem_SIR
    'AP',   latest_dir(fullfile(EX,'AP',  'Results_AP_partobs1_4_*')),            @define_problem_AP
    'AP',   latest_dir(fullfile(EX,'AP',  'Results_AP_HybridCov_partobs1_4_*')),  @define_problem_AP
    'NFKB', latest_dir_with(fullfile(EX,'NFKB','Results_NFKB_*'), 'CUQDyn1_Plus_results.mat'),           @define_problem_NFKB
    'NFKB', latest_dir_with(fullfile(EX,'NFKB','Results_NFKB_*'), 'CUQDyn1_Plus_HybridCov_results.mat'), @define_problem_NFKB
    };

fprintf('\n=== generate_uq_diagnostics: writing uq_diagnostics.xlsx for main runs ===\n');
nok = 0;
for i = 1:size(jobs,1)
    model  = jobs{i,1};
    folder = jobs{i,2};
    probfn = jobs{i,3};
    if isempty(folder)
        fprintf(2, '  %-5s : no result folder found, skipped\n', model);
        continue;
    end
    try
        d = dir(fullfile(folder, '*_results.mat'));
        assert(~isempty(d), 'no *_results.mat in %s', folder);
        S = load(fullfile(d(1).folder, d(1).name));
        results = pick_results(S);
        problem = probfn();
        pnames = cellstr(string(problem.parameters(:)));
        snames = cellstr(string(problem.states(:)));
        if isfield(results,'n_params') && numel(pnames) ~= results.n_params
            pnames = arrayfun(@(j) sprintf('Param%d',j), 1:results.n_params, 'UniformOutput', false)';
        end
        if isfield(results,'nstates') && numel(snames) ~= results.nstates
            snames = arrayfun(@(j) sprintf('State%d',j), 1:results.nstates, 'UniformOutput', false)';
        end
        diagnose_uq_quality(results, folder, pnames, snames, [], []);
        fprintf('  %-5s : OK -> %s\n', model, fullfile(folder,'uq_diagnostics.xlsx'));
        nok = nok + 1;
    catch ME
        fprintf(2, '  %-5s : FAILED (%s)\n', model, ME.message);
    end
end
fprintf('=== generate_uq_diagnostics: %d/%d folders done ===\n\n', nok, size(jobs,1));
end

% -------------------------------------------------------------------------
function results = pick_results(S)
results = [];
fn = fieldnames(S);
for k = 1:numel(fn)
    if isstruct(S.(fn{k})) && isfield(S.(fn{k}), 'Cov_p')
        results = S.(fn{k});
        return;
    end
end
error('no results struct with a Cov_p field');
end

function p = latest_dir(pattern)
% Newest directory matching a glob (timestamped names sort lexically).
d = dir(pattern);
d = d([d.isdir]);
p = '';
if isempty(d); return; end
[~, ix] = sort({d.name});
d = d(ix);
p = fullfile(d(end).folder, d(end).name);
end

function p = latest_dir_with(pattern, mustFile)
% Newest matching directory that contains mustFile (tells the NF-kB FIM and
% HybridCov folders apart, since their names are identical).
d = dir(pattern);
d = d([d.isdir]);
p = '';
if isempty(d); return; end
[~, ix] = sort({d.name});
d = d(ix);
for k = numel(d):-1:1
    cand = fullfile(d(k).folder, d(k).name);
    if exist(fullfile(cand, mustFile), 'file') == 2
        p = cand;
        return;
    end
end
end
