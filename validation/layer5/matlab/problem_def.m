function pb = problem_def(model)
%PROBLEM_DEF The layer-5 problem, identical for the MEIGO server and the MATLAB pipeline.
%
% Same definitions as gen_baseline.m (model, bounds, guess, alpha, budget,
% residual model), plus the loaded data and the option structs, so both MATLAB
% roles of layer 5 see exactly one problem. Puts CUQDyn1_Plus/src, MEIGO64 and
% the model's example directory on the path, and registers cvodes_solver as the
% process-wide ODE solver.

here = fileparts(mfilename('fullpath'));
repo = fullfile(here, '..', '..', '..');
addpath(here);
addpath(fullfile(repo, 'CUQDyn1_Plus', 'src'));
meigoPath = getenv('MEIGO64_PATH');
if isempty(meigoPath)
    meigoPath = fullfile(repo, 'CUQDyn', 'Matlab', 'MEIGO64-master');
end
if ~isfolder(meigoPath)
    error('problem_def:meigo', 'MEIGO64 not found (looked in %s). Set MEIGO64_PATH.', meigoPath);
end
addpath(genpath(meigoPath));

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
        pb.maxeval = 2e4;
    case 'ap'
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
        pb.maxeval = 1e4;
    case 'sir'
        pb.exdir = fullfile(repo, 'CUQDyn1_Plus', 'EXAMPLES', 'SIR');
        pb.dynamics = @prob_mod_dynamics_SIR;
        pb.cost = @prob_mod_cost_SIR;
        pb.nstates = 3;
        pb.n_params = 2;
        pb.true_params = [0.002, 0.5];
        pb.guess_params = [0.001, 0.2];
        pb.lb_params = [0.0001, 0.01];
        pb.ub_params = [0.01, 2.0];
        pb.alp = 0.05;
        pb.dataFile = 'sir_data.csv';
        pb.cost_model = 'known_sigma_sir';
        pb.noise_pct = 10;
        pb.ode_rtol = 1e-8;
        pb.ode_atol = 1e-8;
        pb.maxeval = 2e4;
    otherwise
        error('problem_def:model', 'Unknown model "%s" (lv2|ap|sir|nfkb)', model);
end
% CUQDYN_L5_MAXEVAL overrides the budget, for smoke runs of the whole chain.
budget = getenv('CUQDYN_L5_MAXEVAL');
if ~isempty(budget), pb.maxeval = str2double(budget); end
pb.dataDir = fullfile(pb.exdir, 'data');
addpath(pb.exdir);

[pb.times, pb.all_state_data, pb.y0, pb.observed_data, pb.observed_idx] = ...
    loadStateData(pb.dataDir, pb.dataFile, pb.nstates);
pb.m = numel(pb.times);

opts = cuqdyn_default_options(pb.n_params);
opts.uq.alp = pb.alp;
opts.meigo.maxeval = pb.maxeval;
opts.meigo.iterprint = 0;
if isfield(pb, 'ode_rtol')
    opts.ode.RelTol = pb.ode_rtol;
    opts.ode.AbsTol = pb.ode_atol;
end

% The residual model, as gen_baseline.m derives it: sigma from the true
% trajectory (ode15s here, sigma derivation only - the pipeline never uses it).
[ode_options, ~] = cuqdyn_odeset_from_options(opts.ode);
[~, Y_true] = ode15s(@(t, y) pb.dynamics(t, y, pb.true_params), pb.times, pb.y0, ode_options);
switch pb.cost_model
    case 'known_sigma_traj'
        opts.cost.residual_model = 'known_sigma';
        opts.cost.sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, pb.observed_idx, pb.noise_pct);
        opts.cost.sigma_is_known = true;
    case 'known_sigma_sir'
        opts.cost.residual_model = 'known_sigma';
        opts.cost.sigma = (pb.noise_pct / 100) * mean(Y_true(2:end, 2));
        opts.cost.sigma_is_known = true;
    case 'none'
        % unweighted least squares
end

% Every integration of the pipeline goes through CVODES from here on.
opts.ode.solver = @cvodes_solver;
cuqdyn_set_ode_options(opts.ode);
[~, pb.ode_opts] = cuqdyn_get_ode_options();

pb.opts = opts;
pb.meigo_opts = opts.meigo;
pb.meigo_opts.cost_opts = opts.cost;
pb.cost_opts = cuqdyn_fill_cost_options(opts.cost);
end
