function [UQ_lower, UQ_upper, Cov_p, std_y, fimDiagnostics, fimReliability, Cov_log] = fast_compute_hybrid_uncertainty( ...
    media_tot, observed_data, observed_idx, initial_values_all_states, ...
    times, parameters_init, nstates, n_params, m, ...
    UQ_lower_obs, UQ_upper_obs, alp, dynamics_handle, ODE_solve_handle, ...
    cost_opts, ode_opts, fim_opts)
%FAST_COMPUTE_HYBRID_UNCERTAINTY FIM-only hidden-state delta-method bands.

fprintf('Gaussian UQ for unobserved states...\n');
if nargin < 15 || isempty(cost_opts), cost_opts = struct(); end
if nargin < 16, ode_opts = []; end
if nargin < 17, fim_opts = struct(); end
cost_opts = cuqdyn_fill_cost_options(cost_opts);

res_full = observed_data - media_tot(:, observed_idx);
residuals = cuqdyn_weight_residuals(res_full, cost_opts);
sigma2 = cuqdyn_residual_variance(residuals, n_params, cost_opts);

cost_wrapper = @(p) cost_fun(p, initial_values_all_states, times, ...
    observed_data, observed_idx, ODE_solve_handle, cost_opts, ode_opts);
J_obs = jacobianest_cs(cost_wrapper, parameters_init);

fprintf('   - Computing sensitivity matrix (complex step)...\n');
S = zeros(m, nstates, n_params);
h = 1e-20;
for k = 1:n_params
    p_complex = parameters_init;
    p_complex(k) = p_complex(k) + 1i * h;
    y_complex = call_ode(ODE_solve_handle, initial_values_all_states, ...
        times, p_complex, dynamics_handle, ode_opts);
    S(:, :, k) = imag(y_complex(:, 2:end)) / h;
end

[Cov_p, Cov_log, fimDiagnostics, fimReliability] = cuqdyn_fim_covariance( ...
    J_obs, sigma2, parameters_init, S, fim_opts);
if fimDiagnostics.any_unreliable_bands
    fprintf('   - Warning: FIM weak directions affect %d state band(s); see diagnostics.fim_reliability.\n', ...
        sum(fimReliability.bandUnreliableByState));
end

Var_y = zeros(m, nstates);
for i = 1:m
    St = squeeze(S(i, :, :));
    if nstates == 1, St = St(:)'; end
    Var_y(i, :) = diag(St * Cov_p * St.');
end
std_y = sqrt(max(Var_y, 0));

UQ_lower = NaN(m, nstates);
UQ_upper = NaN(m, nstates);
UQ_lower(1, :) = initial_values_all_states;
UQ_upper(1, :) = initial_values_all_states;

z = norminv(1 - alp);
for j = 1:nstates
    if ismember(j, observed_idx)
        col = find(observed_idx == j);
        UQ_lower(2:end, j) = UQ_lower_obs(2:end, col);
        UQ_upper(2:end, j) = UQ_upper_obs(2:end, col);
    else
        UQ_lower(2:end, j) = media_tot(2:end, j) - z * std_y(2:end, j);
        UQ_upper(2:end, j) = media_tot(2:end, j) + z * std_y(2:end, j);
    end
end

fprintf('FIM UQ complete: Gaussian (unobserved) + CUQDyn1 (observed)\n');

    function r = cost_fun(p, y0, tspan, ydata, obs_idx, ode_fun, local_cost_opts, local_ode_opts)
        sol = call_ode(ode_fun, y0, tspan, p, dynamics_handle, local_ode_opts);
        ysim = sol(:, 2:end);
        r = cuqdyn_weight_residuals(ysim(:, obs_idx) - ydata, local_cost_opts);
        r = r(:);
    end

    function sol = call_ode(ode_fun, y0, tspan, p, dyn_fun, local_ode_opts)
        if isempty(local_ode_opts)
            sol = ode_fun(y0, tspan, p, dyn_fun);
            return;
        end
        try
            sol = ode_fun(y0, tspan, p, dyn_fun, local_ode_opts);
        catch ME
            if strcmp(ME.identifier, 'MATLAB:TooManyInputs')
                sol = ode_fun(y0, tspan, p, dyn_fun);
            else
                rethrow(ME);
            end
        end
    end

end
