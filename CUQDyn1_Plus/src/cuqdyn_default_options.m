function opts = cuqdyn_default_options(n_params, profile)
%CUQDYN_DEFAULT_OPTIONS Central defaults for CUQDyn1_Plus examples.
%
%   opts = cuqdyn_default_options(n_params)
%   opts = cuqdyn_default_options(n_params, profile)
%
% Returns a structured options object used by maintained examples and tests.
% The object groups MEIGO/eSS settings, guarded LOO refit settings, ODE solver
% tolerances, UQ settings, bootstrap settings, plotting/reporting options, and
% residual-cost defaults. Callers usually customize selected fields, then pass
% opts.meigo (with opts.cost attached as meigo_opts.cost_opts) to CUQDyn.
%
% Profiles:
%   'default'     Balanced example settings.
%   'fast'        Lower optimiser/bootstrap budgets for smoke tests.
%   'production' Higher optimiser/bootstrap budgets for final analyses.
%   'sbc'         Settings intended for repeated calibration runs.

if nargin < 1 || isempty(n_params)
    n_params = 1;
end
if nargin < 2 || isempty(profile)
    profile = 'default';
end

n_params = max(1, double(n_params));
profile = lower(char(profile));

opts = struct();
opts.profile = profile;

% Optimiser settings. The maxeval rule scales with model dimension so the
% default is less arbitrary across examples.
opts.meigo = struct();
opts.meigo.maxeval      = n_params * 500;
opts.meigo.log_var      = 1:n_params;
opts.meigo.local.solver = 'lsqnonlin';
opts.meigo.inter_save   = 0;
opts.meigo.iterprint    = 1;

% Refit settings for repeated fits after the initial full-data eSS fit.
% 'global' preserves the original behavior. 'local_after_global' uses a
% guarded local solver initialized at the full-data optimum and falls back
% to eSS when the local refit looks suspicious.
opts.meigo.refit = struct();
opts.meigo.refit.strategy = 'global';
opts.meigo.refit.local_solver = 'lsqnonlin';
opts.meigo.refit.local_maxeval_factor = 100;
opts.meigo.refit.retry_global_on_failure = true;
opts.meigo.refit.max_cost_ratio_from_start = 1.01;
opts.meigo.refit.max_parameter_fold_change = 10;
opts.meigo.refit.bound_tol = 1e-6;
opts.meigo.refit.retry_global_on_bound_hit = false;

% ODE settings used by ODE_solve and the example cost functions through
% cuqdyn_get_ode_options/cuqdyn_set_ode_options.
opts.ode = struct();
opts.ode.solver = 'ode15s';
opts.ode.RelTol = 1e-6;
opts.ode.AbsTol = 1e-8;
opts.ode.NonNegative = [];

% UQ/reporting settings.
opts.uq = struct();
opts.uq.alp = 0.025;

% FIM covariance settings. The covariance returned to callers is always in
% natural parameter units; log parameterization is used internally for FIM
% rank diagnostics and covariance construction when parameters are positive.
opts.fim = struct();
opts.fim.parameterization = 'log';
opts.fim.covariance_method = 'relative_ridge';
opts.fim.relative_ridge = 1e-12;
opts.fim.rank_tol_factor = 100;
opts.fim.weak_fraction_threshold = 0.10;

opts.cost = struct();
opts.cost.residual_model = 'none';
opts.cost.sigma = [];
opts.cost.sigma_is_known = true;
opts.cost.sigma_floor = 1e-12;
opts.cost.sigma_mode = 'explicit';
opts.cost.noise_percent = [];
opts.cost.observed_state_weights = [];

opts.bootstrap = struct();
opts.bootstrap.n_boot = 100;
opts.bootstrap.alp = opts.uq.alp;
opts.bootstrap.meigo_opts = opts.meigo;

opts.parallel = struct();
opts.parallel.use_parallel = true;
opts.parallel.num_workers = [];

opts.reproducibility = struct();
opts.reproducibility.rng_seed = [];

opts.reporting = struct();
opts.reporting.print_options = true;
opts.reporting.save_options = true;

switch profile
    case 'fast'
        opts.meigo.maxeval = n_params * 125;
        opts.meigo.iterprint = 0;
        opts.bootstrap.n_boot = 10;
        opts.bootstrap.meigo_opts = opts.meigo;

    case 'production'
        opts.meigo.maxeval = n_params * 2000;
        opts.ode.RelTol = 1e-8;
        opts.ode.AbsTol = 1e-10;
        opts.bootstrap.n_boot = 250;
        opts.bootstrap.meigo_opts = opts.meigo;

    case 'sbc'
        opts.meigo.maxeval = n_params * 500;
        opts.meigo.iterprint = 0;
        opts.bootstrap.n_boot = 50;
        opts.bootstrap.meigo_opts = opts.meigo;

    case 'default'
        % Keep defaults above.

    otherwise
        error('cuqdyn_default_options:UnknownProfile', ...
            'Unknown CUQDyn options profile: %s', profile);
end

opts.bootstrap.alp = opts.uq.alp;

end
