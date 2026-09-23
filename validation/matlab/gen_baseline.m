function gen_baseline(settings_file, layers, varargin)
%GEN_BASELINE The MATLAB side of layers 2, 4 and 6, as plain text.
%
%   gen_baseline(settings_file)                     layers 2 and 4 (references)
%   gen_baseline(settings_file, [2 4])              the same
%   gen_baseline(settings_file, 6, 'Seeds', 1:10, 'OutDir', dir)
%   gen_baseline(settings_file, 6, 'Seeds', 7, 'OutDir', dir)    one SLURM array task
%
% settings_file describes the problem (see matlab/load_problem.m); it is
% written by run_validation.sh, which is the intended caller:
%
%   validation/run_validation.sh references --problem=lv2     layers 2 and 4
%   validation/run_validation.sh layer 6 --problem=lv2        layer 6
%
% Layers (validation/README.md has the rationale):
%   2  INTEGRATION: ODE trajectory + complex-step sensitivities at FIXED
%      parameters (the true ones when the definition has them). No optimiser.
%   4  UQ REPLAY: one full seeded CUQDyn1_Plus run with parallelism disabled.
%      Exports theta_hat, the LOO ensemble, residuals, bands, Cov_p, std_y -
%      enough for the C harness to replay the whole UQ stage deterministically.
%   6  STATISTICAL END-TO-END: N full runs, one per seed, written to
%      <OutDir>/seed_<k>/ for the distribution-level comparison against N runs
%      of the production CLI (tools/compare_baseline.py).
%
% Layers 2 and 4 are REFERENCES: versioned, one file per problem,
% references/<name>.txt, holding the problem context ([meta], [times], [y0],
% [observed_idx], [sigma], [truth]), the layer-2 sections ([theta_fixed],
% [traj], [sens]) and the layer-4 sections ([theta_hat] ... [meta4]); the C
% harness reads it without MATLAB (validation/c/refio.h). Regenerating one layer
% rewrites its sections and keeps the others. The comparison tolerances of
% every problem live in references/tolerances.txt, maintained by hand; a new
% problem gets a default section there. Layer 6 is a run output: not
% versioned, written wherever 'OutDir' says. Layer 1 comes from
% gen_golden.m and layer 3 from gen_cost_replay.m, next to this file.
%
% Everything is plain text ("rows cols" header + %.17g values). Requirements:
% MATLAB R2020a+, Optimization Toolbox (lsqnonlin inside MEIGO's local search),
% MEIGO64 for layers 4 and 6.

if nargin < 1
    error('gen_baseline:usage', 'Usage: gen_baseline(settings_file, [layers], ''Seeds'', s, ''OutDir'', d)');
end
if nargin < 2 || isempty(layers), layers = [2 4]; end
p = inputParser;
p.addParameter('Seeds', 1:10, @isnumeric);
p.addParameter('OutDir', '', @(s) ischar(s) || isstring(s));
p.parse(varargin{:});
seeds = p.Results.Seeds;

here = fileparts(mfilename('fullpath'));
addpath(here);

pb = load_problem(settings_file);
if any(ismember(layers, [4 6])) && ~pb.has_meigo
    error('gen_baseline:meigo', ...
        'MEIGO64 not found (looked in %s). Layers 4 and 6 need it.', pb.meigo_dir);
end
name = pb.name;
opts = pb.opts;
meigo_opts = pb.meigo_opts;
ode_opts = pb.ode_opts;
times = pb.times;
y0 = pb.y0;
observed_data = pb.observed_data;
observed_idx = pb.observed_idx;
m = pb.m;

% The sections this run produces, merged into references/<name>.txt at the end.
sec_names = {};
sec_bodies = {};
    function add(section, body)
        sec_names{end+1} = section;
        sec_bodies{end+1} = body;
    end

refdir = fullfile(here, '..', 'references');
reffile = fullfile(refdir, [name '.txt']);

%% ---------------------------------------------------- shared context ----
if any(ismember(layers, [2 4]))
    if ~exist(refdir, 'dir'), mkdir(refdir); end
    add('meta', kv_text({ ...
        'model', name; ...
        'matlab_definition', ['define_problem_' pb.matlab_name]; ...
        'alp', pb.alp; ...
        'nstates', pb.nstates; ...
        'n_params', pb.n_params; ...
        'n_obs', numel(observed_idx); ...
        'm', m; ...
        'maxeval', pb.maxeval; ...
        'matlab_version', version}));
    add('times', matrix_text(times(:)));
    add('y0', matrix_text(y0(:)));
    add('observed_idx', matrix_text(observed_idx(:)));   % 1-based!
    if strcmp(opts.cost.residual_model, 'known_sigma')
        add('sigma', matrix_text(opts.cost.sigma(:)));
    end
    add('truth', matrix_text(pb.Y_true));
    ensure_tolerances(fullfile(refdir, 'tolerances.txt'), name);
end

%% ------------------------------------------------------------- layer 2 --
if ismember(2, layers)
    fprintf('=== Layer 2: ODE + complex-step sensitivities at fixed parameters ===\n');

    theta = pb.true_params(:);
    add('theta_fixed', matrix_text(theta));

    sol = ODE_solve(y0, times, theta.', pb.dynamics, ode_opts);
    traj = sol(:, 2:end);
    add('traj', matrix_text(traj));

    % Complex-step sensitivities, verbatim from fast_compute_hybrid_uncertainty.
    % Section body: "m nstates n_params", then n_params blocks of m rows.
    h = 1e-20;
    body = sprintf('%d %d %d\n', m, pb.nstates, pb.n_params);
    for k = 1:pb.n_params
        p_c = theta.';
        p_c(k) = p_c(k) + 1i * h;
        y_c = ODE_solve(y0, times, p_c, pb.dynamics, ode_opts);
        Sk = imag(y_c(:, 2:end)) / h;
        body = [body, rows_text(Sk)]; %#ok<AGROW>
    end
    add('sens', body);
    fprintf('Layer 2 done\n');
end

%% ------------------------------------------------------------- layer 4 --
if ismember(4, layers)
    fprintf('=== Layer 4: one seeded CUQDyn1_Plus run (this calls MEIGO) ===\n');

    seed = 20260819;
    rng(seed, 'twister');

    % CUQDyn1_Plus writes its own result files here; git-ignored (**/matlab_run/).
    resultDir = fullfile(refdir, 'matlab_run', name);
    if ~exist(resultDir, 'dir'), mkdir(resultDir); end

    res = CUQDyn1_Plus(pb.cost, pb.dynamics, pb.nstates, pb.n_params, ...
        pb.guess_params, pb.lb_params, pb.ub_params, pb.alp, ...
        times, pb.all_state_data, y0, observed_data, observed_idx, ...
        resultDir, meigo_opts);

    add('theta_hat', matrix_text(res.parameters_init(:)));
    add('loo_params', matrix_text(res.loo_params));
    add('resid_loo', matrix_text(res.resid_loo));
    add('media_tot', matrix_text(res.media_tot));
    add('q_low', matrix_text(res.UQ_lower));
    add('q_up', matrix_text(res.UQ_upper));
    add('cov_p', matrix_text(res.Cov_p));
    add('std_y', matrix_text(res.std_y));
    add('observed_data', matrix_text(observed_data));

    % media_matrix is m x nstates x (m-1): "m-1 m nstates", then flat blocks.
    body = sprintf('%d %d %d\n', m - 1, m, pb.nstates);
    for k = 1:(m - 1)
        body = [body, rows_text(res.media_matrix(:, :, k))]; %#ok<AGROW>
    end
    add('media_matrix', body);

    % sigma2 as fast_compute_hybrid_uncertainty computes it (1 for known sigma).
    res_full = observed_data - res.media_tot(:, observed_idx);
    wres = cuqdyn_weight_residuals(res_full, opts.cost);
    sigma2 = cuqdyn_residual_variance(wres, pb.n_params, opts.cost);
    add('meta4', kv_text({'seed', seed; 'sigma2', sigma2}));

    fprintf('Layer 4 done\n');
end

if any(ismember(layers, [2 4]))
    write_reference(reffile, sec_names, sec_bodies);
    fprintf('References written to %s\n', reffile);
end

%% ------------------------------------------------------------- layer 6 --
if ismember(6, layers)
    l6 = char(p.Results.OutDir);
    if isempty(l6)
        error('gen_baseline:outdir', 'Layer 6 is a run output: pass ''OutDir''.');
    end
    fprintf('=== Layer 6: %d seeded full runs ===\n', numel(seeds));
    if ~exist(l6, 'dir'), mkdir(l6); end
    % What the report needs about the problem itself, so that layer 6 does not
    % depend on the references having been generated.
    write_matrix(fullfile(l6, 'times.txt'), times(:));
    write_matrix(fullfile(l6, 'truth.txt'), pb.Y_true);

    for s = seeds(:).'
        sdir = fullfile(l6, sprintf('seed_%d', s));
        if exist(fullfile(sdir, 'q_up.txt'), 'file')
            fprintf('seed %d already done, skipping\n', s);
            continue;
        end
        if ~exist(sdir, 'dir'), mkdir(sdir); end

        rng(s, 'twister');
        resultDir = fullfile(sdir, 'matlab_run');
        if ~exist(resultDir, 'dir'), mkdir(resultDir); end

        % Wall clock per seed, so the two sides can be compared on cost as well
        % as on results. The C side writes the same file.
        tseed = tic;
        res = CUQDyn1_Plus(pb.cost, pb.dynamics, pb.nstates, pb.n_params, ...
            pb.guess_params, pb.lb_params, pb.ub_params, pb.alp, ...
            times, pb.all_state_data, y0, observed_data, observed_idx, ...
            resultDir, meigo_opts);
        elapsed = toc(tseed);

        fid = fopen(fullfile(sdir, 'timing.txt'), 'w');
        fprintf(fid, 'seconds %.3f\n', elapsed);
        fclose(fid);

        write_matrix(fullfile(sdir, 'theta_hat.txt'), res.parameters_init(:));
        write_matrix(fullfile(sdir, 'params_median.txt'), median(res.loo_params, 1).');
        write_matrix(fullfile(sdir, 'q_low.txt'), res.UQ_lower);
        write_matrix(fullfile(sdir, 'q_up.txt'), res.UQ_upper);
        fprintf('seed %d done in %.1f s\n', s, elapsed);
    end
    fprintf('Layer 6 written to %s\n', l6);
end

fprintf('\ngen_baseline: %s done\n', name);
end

%% ---------------------------------------------------------------- local --

function t = rows_text(M)
% The rows of M, "%.17g " per value, one line per row.
t = '';
for i = 1:size(M, 1)
    t = [t, sprintf('%.17g ', M(i, :)), newline]; %#ok<AGROW>
end
end

function t = matrix_text(M)
% The body of an array section: "rows cols" then the rows.
t = [sprintf('%d %d\n', size(M, 1), size(M, 2)), rows_text(M)];
end

function t = kv_text(kv)
% The body of a "key value" section (numbers %.17g, text as it is).
t = '';
for i = 1:size(kv, 1)
    v = kv{i, 2};
    if ischar(v) || isstring(v)
        t = [t, sprintf('%s %s\n', kv{i, 1}, char(v))]; %#ok<AGROW>
    else
        t = [t, sprintf('%s %.17g\n', kv{i, 1}, v)]; %#ok<AGROW>
    end
end
end

function write_reference(path, names, bodies)
% Merge the sections just produced into the reference file of the problem:
% a section that was regenerated replaces the old one, the others are kept,
% and the file is written in the canonical order so that a regeneration of
% one layer leaves a minimal diff.
order = {'meta', 'times', 'y0', 'observed_idx', 'sigma', 'truth', ...
    'theta_fixed', 'traj', 'sens', ...
    'theta_hat', 'loo_params', 'resid_loo', 'media_tot', 'q_low', 'q_up', ...
    'cov_p', 'std_y', 'observed_data', 'media_matrix', 'meta4'};
[old_names, old_bodies] = read_sections(path);
all_names = [old_names, names];
all_bodies = [old_bodies, bodies];
known = [order, setdiff(all_names, order, 'stable')];
fid = fopen(path, 'w');
if fid < 0, error('gen_baseline:io', 'cannot write %s', path); end
for i = 1:numel(known)
    k = find(strcmp(all_names, known{i}), 1, 'last');   % the new one wins
    if isempty(k), continue; end
    fprintf(fid, '[%s]\n', known{i});
    fprintf(fid, '%s', all_bodies{k});
end
fclose(fid);
end

function write_matrix(path, M)
% Layer-6 run outputs keep the one-array-per-file format compare_baseline.py reads.
fid = fopen(path, 'w');
if fid < 0, error('gen_baseline:io', 'cannot write %s', path); end
fprintf(fid, '%s', matrix_text(M));
fclose(fid);
end

function ensure_tolerances(path, name)
% tolerances.txt is maintained by hand: the tolerances of a problem are a
% judgement on its conditioning (README, "Tolerances"), not something to
% regenerate. A new problem gets a section with the values that fit a
% well-conditioned non-stiff model (lv2, sir); an existing section is never
% touched.
%   layer2_traj      both sides integrate at the same RelTol; two correct
%                    solvers (ode15s vs CVODES BDF) agree to roughly 100x that.
%   layer2_sens      sensitivities amplify integration error, and CVODES uses
%                    internal finite differences for the sensitivity RHS while
%                    MATLAB's complex step is exact: the loosest deterministic
%                    layer.
%   layer4_conformal identical inputs, identical quantile algorithm: anything
%                    beyond float round-trip noise is a transpilation bug.
%   layer4_delta     inherits layer2_sens through J and S, then goes through
%                    the FIM inverse; loosen it for an ill-conditioned FIM and
%                    read failures together with the printed rank and condition
%                    number (nfkb also sets layer4_covp).
%   layer5_cost      how far the two CVODES builds may disagree on J at the same
%                    theta in the lock-step check: the integration tolerance,
%                    reached on the rare evaluations where the two integrators
%                    take a different step sequence.
[names, ~] = read_sections(path);
if any(strcmp(names, name)), return; end
fid = fopen(path, 'a');
if fid < 0, error('gen_baseline:io', 'cannot write %s', path); end
fprintf(fid, '[%s]\n', name);
fprintf(fid, 'layer2_traj 1e-4\n');
fprintf(fid, 'layer2_sens 5e-3\n');
fprintf(fid, 'layer4_conformal 1e-9\n');
fprintf(fid, 'layer4_delta 1e-2\n');
fprintf(fid, 'layer5_cost 1e-4\n');
fclose(fid);
end
