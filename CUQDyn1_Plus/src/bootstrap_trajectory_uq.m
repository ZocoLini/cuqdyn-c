function boot = bootstrap_trajectory_uq(results, dynamics_handle, cost_handle, ...
    lb_params, ub_params, resultDir, boot_opts)
%BOOTSTRAP_TRAJECTORY_UQ  Parametric bootstrap trajectory uncertainty.
%
%   boot = bootstrap_trajectory_uq(results, dynamics_handle, cost_handle, ...
%       lb_params, ub_params, resultDir, boot_opts)
%
%   Starting from an existing CUQDyn1_Plus or CUQDyn1_Plus_HybridCov results
%   struct, this optional post-fit workflow:
%     1. estimates observed-state noise from post-initial residuals,
%     2. simulates bootstrap observed datasets around the fitted trajectory,
%     3. refits parameters for each bootstrap dataset,
%     4. propagates each refit through the ODE,
%     5. returns empirical trajectory quantile bands.
%
%   Interpretation:
%     The returned bands are latent deterministic ODE trajectory bands induced
%     by parameter uncertainty and the assumed bootstrap noise model. They are
%     not noisy-observation prediction intervals unless observation noise is
%     added separately.
%
%   Optional boot_opts fields:
%     n_boot       number of bootstrap refits (default 100)
%     alp          one-sided tail probability (default results.alp or 0.025)
%     meigo_opts   options passed to MEIGO (default struct())
%     fit_handle   custom fit handle for tests or alternative optimizers
%     save_file    output MAT filename (default bootstrap_trajectory_uq.mat)

if nargin < 7 || isempty(boot_opts)
    boot_opts = struct();
end
if ~isfield(boot_opts, 'n_boot'), boot_opts.n_boot = 100; end
if ~isfield(boot_opts, 'alp')
    if isfield(results, 'alp')
        boot_opts.alp = results.alp;
    else
        boot_opts.alp = 0.025;
    end
end
if ~isfield(boot_opts, 'meigo_opts'), boot_opts.meigo_opts = struct(); end
boot_opts.meigo_opts = cuqdyn_fill_meigo_options(boot_opts.meigo_opts, results.n_params);
if isfield(boot_opts.meigo_opts, 'cost_opts')
    cost_opts = cuqdyn_fill_cost_options(boot_opts.meigo_opts.cost_opts);
elseif isfield(results, 'options') && isfield(results.options, 'cost')
    cost_opts = cuqdyn_fill_cost_options(results.options.cost);
else
    cost_opts = cuqdyn_fill_cost_options();
end
if isfield(boot_opts.meigo_opts, 'cost_opts')
    boot_opts.meigo_opts = rmfield(boot_opts.meigo_opts, 'cost_opts');
end
if isfield(boot_opts.meigo_opts, 'refit')
    boot_opts.meigo_opts = rmfield(boot_opts.meigo_opts, 'refit');
end
if ~isfield(boot_opts, 'save_file'), boot_opts.save_file = 'bootstrap_trajectory_uq.mat'; end

resultDir = char(resultDir);
if ~exist(resultDir, 'dir')
    mkdir(resultDir);
end

times = results.times(:);
media_tot = results.media_tot;
observed_idx = results.observed_idx(:)';
observed_data = results.observed_data;
initial_values = results.initial_values_all_states;
parameters_init = results.parameters_init;
nstates = results.nstates;
n_params = results.n_params;
n_boot = boot_opts.n_boot;
alp = boot_opts.alp;
[~, ode_opts] = cuqdyn_get_ode_options();

if size(media_tot, 1) ~= numel(times)
    error('bootstrap_trajectory_uq:SizeMismatch', ...
        'results.times and results.media_tot must have matching row counts.');
end

residuals = observed_data(2:end,:) - media_tot(2:end, observed_idx);
sigma_obs = sqrt(mean(residuals.^2, 1, 'omitnan'));
sigma_obs(~isfinite(sigma_obs)) = 0;

bootstrap_params = NaN(n_boot, n_params);
bootstrap_trajectories = NaN(numel(times), nstates, n_boot);
success = false(n_boot, 1);
failure_messages = strings(n_boot, 1);

fprintf('\n=== Parametric bootstrap trajectory UQ ===\n');
fprintf('Bootstrap replicates: %d\n', n_boot);

for b = 1:n_boot
    y_boot = media_tot(:, observed_idx);
    if numel(times) > 1
        noise = randn(numel(times)-1, numel(observed_idx)) .* sigma_obs;
        y_boot(2:end,:) = y_boot(2:end,:) + noise;
    end
    y_boot(1,:) = observed_data(1,:);

    try
        if isfield(boot_opts, 'fit_handle') && ~isempty(boot_opts.fit_handle)
            params_b = boot_opts.fit_handle(times, y_boot, observed_idx, ...
                initial_values, parameters_init, b);
        else
            params_b = fit_with_meigo(cost_handle, dynamics_handle, ...
                lb_params, ub_params, parameters_init, times, y_boot, ...
                observed_idx, initial_values, boot_opts.meigo_opts, ode_opts, cost_opts);
        end

        sol_b = ODE_solve(initial_values, times, params_b, dynamics_handle, ode_opts);
        bootstrap_params(b,:) = params_b(:)';
        bootstrap_trajectories(:,:,b) = sol_b(:, 2:end);
        success(b) = true;
    catch ME
        failure_messages(b) = string(ME.message);
    end

    if mod(b, max(1, ceil(n_boot/10))) == 0 || b == n_boot
        fprintf('  %d / %d bootstrap replicates complete (%d successful)\n', ...
            b, n_boot, sum(success));
    end
end

if ~any(success)
    error('bootstrap_trajectory_uq:NoSuccessfulReplicates', ...
        'No bootstrap refits succeeded.');
end

traj_success = bootstrap_trajectories(:,:,success);
UQ_lower_boot = quantile(traj_success, alp, 3);
UQ_upper_boot = quantile(traj_success, 1 - alp, 3);

mean_width = squeeze(mean(UQ_upper_boot - UQ_lower_boot, 1, 'omitnan'));
state_names = arrayfun(@(j) sprintf('State%d', j), 1:nstates, 'UniformOutput', false)';
summaryTable = table((1:nstates)', state_names, mean_width(:), ...
    'VariableNames', {'StateIndex', 'StateName', 'MeanBootstrapBandWidth'});

boot = struct();
boot.times = times;
boot.alp = alp;
boot.n_boot = n_boot;
boot.n_success = sum(success);
boot.success = success;
boot.failure_messages = failure_messages;
boot.sigma_obs = sigma_obs;
boot.bootstrap_params = bootstrap_params;
boot.bootstrap_trajectories = bootstrap_trajectories;
boot.UQ_lower = UQ_lower_boot;
boot.UQ_upper = UQ_upper_boot;
boot.summaryTable = summaryTable;
boot.options = boot_opts;
[~, boot.options.ode] = cuqdyn_get_ode_options();
boot.options.cost = cost_opts;

save(fullfile(resultDir, boot_opts.save_file), 'boot', '-v7.3');
save_run_options(resultDir, struct('bootstrap', boot_opts, ...
    'cost', cost_opts, 'ode', boot.options.ode), ...
    'bootstrap_run_options');
writetable(summaryTable, fullfile(resultDir, 'bootstrap_trajectory_uq_summary.xlsx'), ...
    'Sheet', 'Summary');

fprintf('Successful bootstrap replicates: %d / %d\n', boot.n_success, n_boot);
disp(summaryTable);
fprintf('Bootstrap trajectory UQ saved to %s\n', fullfile(resultDir, boot_opts.save_file));

end

function params = fit_with_meigo(cost_handle, dynamics_handle, lb_params, ub_params, ...
    guess_params, times, observed_data, observed_idx, initial_values, meigo_opts, ode_opts, cost_opts)
    if isempty(cost_handle)
        error('bootstrap_trajectory_uq:MissingCostHandle', ...
            'cost_handle is required unless boot_opts.fit_handle is supplied.');
    end
    if isempty(lb_params) || isempty(ub_params)
        error('bootstrap_trajectory_uq:MissingBounds', ...
            'lb_params and ub_params are required unless boot_opts.fit_handle is supplied.');
    end

    n_params = numel(guess_params);
    meigo_opts = cuqdyn_fill_meigo_options(meigo_opts, n_params);
    if isfield(meigo_opts, 'cost_opts')
        meigo_opts = rmfield(meigo_opts, 'cost_opts');
    end
    if isfield(meigo_opts, 'refit')
        meigo_opts = rmfield(meigo_opts, 'refit');
    end

    problem = struct();
    problem.f = cost_handle;
    problem.x_L = lb_params;
    problem.x_U = ub_params;
    problem.x_0 = guess_params;

    fit = MEIGO(problem, meigo_opts, 'ESS', times, observed_data, ...
        observed_idx, dynamics_handle, initial_values, ode_opts, cost_opts);
    params = fit.xbest;
end
