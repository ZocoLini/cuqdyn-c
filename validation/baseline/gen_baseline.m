function gen_baseline(model, layers, seeds, outdir)
%GEN_BASELINE Export a MATLAB baseline for the C port, as plain text.
%
%   gen_baseline('lv2')                 layers 2 and 3, default output dir
%   gen_baseline('nfkb', [2 3])         same, NF-kB
%   gen_baseline('lv2', 4, 1:10)        layer 4, seeds 1..10
%   gen_baseline('nfkb', 4, 7)          layer 4, only seed 7 (for SLURM arrays)
%
% Models:
%   'lv2'   Lotka-Volterra, 2 states, prey observed / predator hidden.
%           Mirrors EXAMPLES/LV/run_LV2_CUQDyn1_Plus_partobs_example.m and the
%           C-side example-files/lv2_partobs_* pair (same data, same bounds).
%   'nfkb'  NF-kB, 15 states / 29 params, 10 observed. Mirrors
%           EXAMPLES/NFKB/run_NFKB_example_CUQDyn1plus.m and the C-side
%           example-files/nfkb_* pair.
%
% Layers (see validation/README.md for the layering rationale):
%   2  INTEGRATION: ODE trajectory + complex-step sensitivities at FIXED true
%      parameters. No optimiser at all. Pins down CVODES-vs-complex-step.
%   3  UQ REPLAY: one full seeded CUQDyn1_Plus run with parallelism disabled.
%      Exports theta_hat, the LOO ensemble, residuals, bands, Cov_p, std_y -
%      enough for the C harness to replay the whole UQ stage deterministically.
%   4  STATISTICAL END-TO-END: N full runs, one per seed. Exports per-seed
%      theta_hat, median params and bands, for a distribution-level comparison
%      against N C runs (compare_baseline.py does that part).
%
% Everything is written as plain text ("rows cols" header + %.17g values,
% the same format validation/golden uses), so the C side needs no MATLAB.
%
% Requirements: MATLAB R2020a+, Optimization Toolbox (lsqnonlin inside
% MEIGO's local search). MEIGO64 is picked up from $MEIGO64_PATH or from
% CUQDyn/Matlab/MEIGO64-master in this repository.

if nargin < 1
    error('gen_baseline:model', 'Usage: gen_baseline(''lv2''|''nfkb'', [layers], [seeds], [outdir])');
end
if nargin < 2 || isempty(layers), layers = [2 3]; end
if nargin < 3 || isempty(seeds),  seeds  = 1:10; end

here = fileparts(mfilename('fullpath'));
repo = fullfile(here, '..', '..');

if nargin < 4 || isempty(outdir)
    outdir = fullfile(here, 'matlab', model);
end

% --- Paths: CUQDyn1_Plus sources, the example dir of the model, MEIGO ---
addpath(fullfile(repo, 'CUQDyn1_Plus', 'src'));

meigoPath = getenv('MEIGO64_PATH');
if isempty(meigoPath)
    meigoPath = fullfile(repo, 'CUQDyn', 'Matlab', 'MEIGO64-master');
end
if isfolder(meigoPath)
    addpath(genpath(meigoPath));
elseif any(ismember(layers, [3 4]))
    error('gen_baseline:meigo', ...
        'MEIGO64 not found (looked in %s). Set MEIGO64_PATH. Layers 4/5 need it.', meigoPath);
end

pb = local_problem(model, repo);
addpath(pb.exdir);

if ~exist(outdir, 'dir'), mkdir(outdir); end

% --- Load data exactly as the example runners do ---
[times, all_state_data, y0, observed_data, observed_idx] = ...
    loadStateData(pb.dataDir, pb.dataFile, pb.nstates);
m = numel(times);

% --- Options: identical to the example runners ---
opts = cuqdyn_default_options(pb.n_params);
opts.uq.alp = pb.alp;
opts.meigo.maxeval = pb.maxeval;
opts.meigo.iterprint = 0;
if isfield(pb, 'ode_rtol')   % SIR overrides the defaults, the rest keep 1e-6/1e-8
    opts.ode.RelTol = pb.ode_rtol;
    opts.ode.AbsTol = pb.ode_atol;
end
cuqdyn_set_ode_options(opts.ode);
[~, ode_opts] = cuqdyn_get_ode_options();

% Residual error model, replicated per model from its example runner.
[ode_options, ~] = cuqdyn_get_ode_options();
[~, Y_true] = ode15s(@(t, y) pb.dynamics(t, y, pb.true_params), times, y0, ode_options);
switch pb.cost_model
    case 'known_sigma_traj'
        % lv2 / nfkb: sigma_j = noise_pct% of the mean true trajectory.
        opts.cost.residual_model = 'known_sigma';
        opts.cost.sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, pb.noise_pct);
        opts.cost.sigma_is_known = true;
    case 'known_sigma_sir'
        % run_SIR_CUQDyn1Plus.m: mean over t>0 of the infected state only.
        opts.cost.residual_model = 'known_sigma';
        opts.cost.sigma = (pb.noise_pct / 100) * mean(Y_true(2:end, 2));
        opts.cost.sigma_is_known = true;
    case 'none'
        % AP: real measurement data, unweighted least squares (the default).
    otherwise
        error('gen_baseline:cost', 'Unknown cost_model %s', pb.cost_model);
end

meigo_opts = opts.meigo;
meigo_opts.cost_opts = opts.cost;
% Reproducibility: the LOO loop must not run under parfor, or the rng
% stream is split across workers and the run is not repeatable.
meigo_opts.parallel.use_parallel = false;

% Shared context for every layer.
write_matrix(fullfile(outdir, 'times.txt'), times(:));
write_matrix(fullfile(outdir, 'y0.txt'), y0(:));
write_matrix(fullfile(outdir, 'observed_idx.txt'), observed_idx(:));   % 1-based!
if strcmp(opts.cost.residual_model, 'known_sigma')
    write_matrix(fullfile(outdir, 'sigma.txt'), opts.cost.sigma(:));
end
write_matrix(fullfile(outdir, 'truth.txt'), Y_true);
write_tolerances(fullfile(outdir, 'tol.txt'), model);

fid = fopen(fullfile(outdir, 'meta.txt'), 'w');
fprintf(fid, 'model %s\n', model);
fprintf(fid, 'alp %.17g\n', pb.alp);
fprintf(fid, 'nstates %d\n', pb.nstates);
fprintf(fid, 'n_params %d\n', pb.n_params);
fprintf(fid, 'n_obs %d\n', numel(observed_idx));
fprintf(fid, 'm %d\n', m);
fprintf(fid, 'maxeval %d\n', pb.maxeval);
fprintf(fid, 'noise_pct %g\n', pb.noise_pct);
fprintf(fid, 'matlab_version %s\n', version);
fclose(fid);

%% ------------------------------------------------------------- layer 2 --
if ismember(2, layers)
    fprintf('=== Layer 2: ODE + complex-step sensitivities at true parameters ===\n');
    l2 = fullfile(outdir, 'layer2');
    if ~exist(l2, 'dir'), mkdir(l2); end

    theta = pb.true_params(:);
    write_matrix(fullfile(l2, 'theta_fixed.txt'), theta);

    sol = ODE_solve(y0, times, theta.', pb.dynamics, ode_opts);
    traj = sol(:, 2:end);
    write_matrix(fullfile(l2, 'traj.txt'), traj);

    % Complex-step sensitivities, verbatim from fast_compute_hybrid_uncertainty.
    h = 1e-20;
    fid = fopen(fullfile(l2, 'sens.txt'), 'w');
    fprintf(fid, '%d %d %d\n', m, pb.nstates, pb.n_params);
    for k = 1:pb.n_params
        p_c = theta.';
        p_c(k) = p_c(k) + 1i * h;
        y_c = ODE_solve(y0, times, p_c, pb.dynamics, ode_opts);
        Sk = imag(y_c(:, 2:end)) / h;
        for i = 1:m
            fprintf(fid, '%.17g ', Sk(i, :));
            fprintf(fid, '\n');
        end
    end
    fclose(fid);
    fprintf('Layer 2 written to %s\n', l2);
end

%% ------------------------------------------------------------- layer 3 --
if ismember(3, layers)
    fprintf('=== Layer 3: one seeded CUQDyn1_Plus run (this calls MEIGO) ===\n');
    l3 = fullfile(outdir, 'layer3');
    if ~exist(l3, 'dir'), mkdir(l3); end

    seed = 20260819;
    rng(seed, 'twister');

    resultDir = fullfile(l3, 'matlab_run');
    if ~exist(resultDir, 'dir'), mkdir(resultDir); end

    res = CUQDyn1_Plus(pb.cost, pb.dynamics, pb.nstates, pb.n_params, ...
        pb.guess_params, pb.lb_params, pb.ub_params, pb.alp, ...
        times, all_state_data, y0, observed_data, observed_idx, ...
        resultDir, meigo_opts);

    write_matrix(fullfile(l3, 'theta_hat.txt'), res.parameters_init(:));
    write_matrix(fullfile(l3, 'loo_params.txt'), res.loo_params);
    write_matrix(fullfile(l3, 'resid_loo.txt'), res.resid_loo);
    write_matrix(fullfile(l3, 'media_tot.txt'), res.media_tot);
    write_matrix(fullfile(l3, 'q_low.txt'), res.UQ_lower);
    write_matrix(fullfile(l3, 'q_up.txt'), res.UQ_upper);
    write_matrix(fullfile(l3, 'cov_p.txt'), res.Cov_p);
    write_matrix(fullfile(l3, 'std_y.txt'), res.std_y);
    write_matrix(fullfile(l3, 'observed_data.txt'), observed_data);

    % media_matrix is m x nstates x (m-1); flat blocks, custom header.
    fid = fopen(fullfile(l3, 'media_matrix.txt'), 'w');
    fprintf(fid, '%d %d %d\n', m - 1, m, pb.nstates);
    for k = 1:(m - 1)
        for i = 1:m
            fprintf(fid, '%.17g ', res.media_matrix(i, :, k));
            fprintf(fid, '\n');
        end
    end
    fclose(fid);

    % sigma2 as fast_compute_hybrid_uncertainty computes it (1 for known sigma).
    res_full = observed_data - res.media_tot(:, observed_idx);
    wres = cuqdyn_weight_residuals(res_full, opts.cost);
    sigma2 = cuqdyn_residual_variance(wres, pb.n_params, opts.cost);

    fid = fopen(fullfile(l3, 'meta4.txt'), 'w');
    fprintf(fid, 'seed %d\n', seed);
    fprintf(fid, 'sigma2 %.17g\n', sigma2);
    fclose(fid);

    fprintf('Layer 3 written to %s\n', l3);
end

%% ------------------------------------------------------------- layer 4 --
if ismember(4, layers)
    fprintf('=== Layer 4: %d seeded full runs ===\n', numel(seeds));
    l4 = fullfile(outdir, 'layer4');
    if ~exist(l4, 'dir'), mkdir(l4); end

    for s = seeds(:).'
        sdir = fullfile(l4, sprintf('seed_%d', s));
        if exist(fullfile(sdir, 'q_up.txt'), 'file')
            fprintf('seed %d already done, skipping\n', s);
            continue;
        end
        if ~exist(sdir, 'dir'), mkdir(sdir); end

        rng(s, 'twister');
        resultDir = fullfile(sdir, 'matlab_run');
        if ~exist(resultDir, 'dir'), mkdir(resultDir); end

        res = CUQDyn1_Plus(pb.cost, pb.dynamics, pb.nstates, pb.n_params, ...
            pb.guess_params, pb.lb_params, pb.ub_params, pb.alp, ...
            times, all_state_data, y0, observed_data, observed_idx, ...
            resultDir, meigo_opts);

        write_matrix(fullfile(sdir, 'theta_hat.txt'), res.parameters_init(:));
        write_matrix(fullfile(sdir, 'params_median.txt'), median(res.loo_params, 1).');
        write_matrix(fullfile(sdir, 'q_low.txt'), res.UQ_lower);
        write_matrix(fullfile(sdir, 'q_up.txt'), res.UQ_upper);
        fprintf('seed %d done\n', s);
    end
    fprintf('Layer 4 written to %s\n', l4);
end

fprintf('\nBaseline export complete: %s\n', outdir);
end

%% ---------------------------------------------------------------- local --

function pb = local_problem(model, repo)
switch lower(model)
    case 'lv2'
        pb.exdir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'LV');
        pb.dynamics = @prob_mod_dynamics_LV;
        pb.cost = @prob_mod_cost_LV;
        pb.nstates = 2;
        pb.n_params = 4;
        pb.true_params = [0.5, 0.02, 0.02, 0.5];
        pb.guess_params = pb.true_params * 0.8;
        pb.lb_params = pb.true_params * 0.2;
        pb.ub_params = pb.true_params * 2.0;
        pb.alp = 0.025;
        pb.dataFile = 'lv2_synthetic_data_noi10_partobs_1.csv';
        pb.cost_model = 'known_sigma_traj';
        pb.noise_pct = 10;
        % The example script uses the default budget (n_params*500 = 2000);
        % the C config example-files/lv2_partobs_ess_serial_config.xml uses
        % 2e4. The baseline matches the C side so layer 4 compares like with
        % like.
        pb.maxeval = 2e4;
    case 'nfkb'
        pb.exdir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'NFKB');
        pb.dynamics = @prob_mod_dynamics_NFKB;
        pb.cost = @prob_mod_cost_NFKB;
        pb.nstates = 15;
        pb.n_params = 29;
        pb.true_params = [0.5 0.2 0.1 1 0.1 5e-7 0.0001 0.0004 0.5 ...
            0.0001 0.00002 5e-7 0.0001 0.0004 0.5 0.0003 ...
            0.0025 0.1 0.0015 0.000025 0.000125 5 ...
            0.0025 0.01 0.001 0.0005 5e-7 0.0001 0.0004];
        pb.guess_params = pb.true_params * 0.8;
        pb.lb_params = pb.true_params * 0.1;
        pb.ub_params = pb.true_params * 4.0;
        pb.alp = 0.05;
        pb.dataFile = 'NFKB_synthetic_data_5n_36st_partobs10.csv';
        pb.cost_model = 'known_sigma_traj';
        pb.noise_pct = 5;
        % run_NFKB_example_CUQDyn1plus.m uses 2e4. The stock C config uses
        % 1e5; the C side of the baseline runs the 2e4 copy in
        % validation/baseline/nfkb_ess_serial_2e4.xml for a fair comparison.
        pb.maxeval = 2e4;
    case 'ap'
        % Mirrors run_AP_CUQDyn1Plus_partobs_example.m: real measurement
        % data, y1-y4 observed / y5 hidden, unweighted cost.
        pb.exdir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'AP');
        pb.dynamics = @prob_mod_dynamics_AP;
        pb.cost = @prob_mod_cost_AP;
        pb.nstates = 5;
        pb.n_params = 5;
        pb.true_params = [5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05];
        pb.guess_params = pb.true_params * 0.8;
        pb.lb_params = pb.true_params * 0.05;
        pb.ub_params = pb.true_params * 5.0;
        pb.alp = 0.05;
        pb.dataFile = 'AP_measurementData_1_4.csv';
        pb.cost_model = 'none';
        pb.noise_pct = 0;
        pb.maxeval = 1e4;   % n_params * 2000, as the runner sets
    case 'sir'
        % Mirrors run_SIR_CUQDyn1Plus.m: only the infected are measured.
        pb.exdir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'SIR');
        pb.dynamics = @prob_mod_dynamics_SIR;
        pb.cost = @prob_mod_cost_SIR;
        pb.nstates = 3;
        pb.n_params = 2;
        pb.true_params = [0.002, 0.5];
        pb.guess_params = [0.001, 0.2];     % absolute, not a multiple of true
        pb.lb_params = [0.0001, 0.01];
        pb.ub_params = [0.01, 2.0];
        pb.alp = 0.05;
        pb.dataFile = 'sir_data.csv';
        pb.cost_model = 'known_sigma_sir';
        pb.noise_pct = 10;
        pb.ode_rtol = 1e-8;                 % the runner overrides the defaults
        pb.ode_atol = 1e-8;
        % The runner keeps the default budget (n_params*500 = 1000); the C
        % config uses 2e4. Matched to the C side, like lv2.
        pb.maxeval = 2e4;
    otherwise
        error('gen_baseline:model', 'Unknown model "%s". Use lv2, nfkb, ap or sir.', model);
end
pb.dataDir = fullfile(pb.exdir, 'data');
end

function write_matrix(path, M)
fid = fopen(path, 'w');
if fid < 0, error('gen_baseline:io', 'cannot write %s', path); end
fprintf(fid, '%d %d\n', size(M, 1), size(M, 2));
for i = 1:size(M, 1)
    fprintf(fid, '%.17g ', M(i, :));
    fprintf(fid, '\n');
end
fclose(fid);
end

function write_tolerances(path, model)
% Comparison tolerances for the C harness, per model. Rationale:
%   layer2_traj      both sides integrate at RelTol 1e-6; two correct solvers
%                    (ode15s vs CVODES BDF) agree to roughly that order.
%   layer2_sens      sensitivities amplify integration error; CVODES also uses
%                    internal finite differences for the sensitivity RHS while
%                    MATLAB's complex step is exact, so this is the loosest
%                    deterministic layer. Differences well beyond it point at
%                    the TODO item "verificar sensitivities".
%   layer3_conformal identical inputs, identical quantile algorithm: anything
%                    beyond float round-trip noise is a transpilation bug.
%   layer3_delta     inherits layer2_sens through J and S, then goes through
%                    the FIM inverse. For NF-kB (cond ~ 6e8) the covariance is
%                    regularisation-dominated, hence the much looser bound -
%                    read failures there together with the printed rank and
%                    condition number.
fid = fopen(path, 'w');
switch lower(model)
    case 'lv2'
        fprintf(fid, 'layer2_traj 1e-4\n');
        fprintf(fid, 'layer2_sens 5e-3\n');
        fprintf(fid, 'layer3_conformal 1e-9\n');
        fprintf(fid, 'layer3_delta 1e-2\n');
    case 'nfkb'
        fprintf(fid, 'layer2_traj 5e-4\n');
        fprintf(fid, 'layer2_sens 1e-2\n');
        fprintf(fid, 'layer3_conformal 1e-9\n');
        fprintf(fid, 'layer3_delta 1e-1\n');
        % cond(FIM) ~ 3e8: the element-wise covariance is regularisation-
        % dominated in the weak directions on BOTH sides, so it is excluded
        % from the gate; bands and std_y remain the meaningful comparison.
        fprintf(fid, 'layer3_covp 1e3\n');
    case 'ap'
        % Long horizon (t up to 36420) with tiny rate constants; the
        % integration error accumulates more than in lv2, so slightly wider.
        fprintf(fid, 'layer2_traj 5e-4\n');
        fprintf(fid, 'layer2_sens 1e-2\n');
        fprintf(fid, 'layer3_conformal 1e-9\n');
        fprintf(fid, 'layer3_delta 5e-2\n');
    case 'sir'
        fprintf(fid, 'layer2_traj 1e-4\n');
        fprintf(fid, 'layer2_sens 5e-3\n');
        fprintf(fid, 'layer3_conformal 1e-9\n');
        fprintf(fid, 'layer3_delta 1e-2\n');
end
fclose(fid);
end
