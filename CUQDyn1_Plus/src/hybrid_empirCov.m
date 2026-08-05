function [UQ_lower, UQ_upper, Cov_p_hyb, std_y, Cov_p_fim, Cov_p_loo, R_loo, D_fim, fimDiagnostics, fimReliability, Cov_log] = hybrid_empirCov( ...
    media_tot, observed_data, observed_idx, initial_values_all_states, ...
    times, parameters_init, nstates, n_params, m, ...
    UQ_lower_obs, UQ_upper_obs, alp, dynamics_handle, ODE_solve_handle, ...
    loo_params, cost_opts, ode_opts, fim_opts)
%HYBRID_EMPIRCOV Hybrid FIM-scale plus LOO-correlation UQ bands.

fprintf('Hybrid FIM-scale + LOO-correlation UQ for unobserved states...\n');
if nargin < 16 || isempty(cost_opts), cost_opts = struct(); end
if nargin < 17, ode_opts = []; end
if nargin < 18, fim_opts = struct(); end
cost_opts = cuqdyn_fill_cost_options(cost_opts);

res_full = observed_data - media_tot(:, observed_idx);
residuals = cuqdyn_weight_residuals(res_full, cost_opts);
sigma2 = cuqdyn_residual_variance(residuals, n_params, cost_opts);
fprintf('   - Estimated sigma2 = %.6g  (sigma = %.6g)\n', sigma2, sqrt(sigma2));

cost_wrapper = @(p) cost_fun_local(p, initial_values_all_states, times, ...
    observed_data, observed_idx, ODE_solve_handle, dynamics_handle, ...
    cost_opts, ode_opts);
J_obs = jacobianest_cs(cost_wrapper, parameters_init);

fprintf('   - Computing sensitivity matrix (complex step, h=1e-20)...\n');
S = zeros(m, nstates, n_params);
h = 1e-20;
for k = 1:n_params
    p_complex = parameters_init;
    p_complex(k) = p_complex(k) + 1i * h;
    y_complex = call_ode(ODE_solve_handle, initial_values_all_states, ...
        times, p_complex, dynamics_handle, ode_opts);
    S(:, :, k) = imag(y_complex(:, 2:end)) / h;
end

[Cov_p_fim, Cov_log, fimDiagnostics, fimReliability] = cuqdyn_fim_covariance( ...
    J_obs, sigma2, parameters_init, S, fim_opts);
if fimDiagnostics.any_unreliable_bands
    fprintf('   - Warning: FIM weak directions affect %d state band(s); see diagnostics.fim_reliability.\n', ...
        sum(fimReliability.bandUnreliableByState));
end

D_fim = sqrt(max(diag(Cov_p_fim), 0));
fprintf('   - FIM marginal std devs:  ');
fprintf('%.4g  ', D_fim); fprintf('\n');

Cov_p_loo = cov(loo_params) + 1e-14 * eye(n_params);
D_loo = sqrt(diag(Cov_p_loo));
fprintf('   - LOO marginal std devs:  ');
fprintf('%.4g  ', D_loo); fprintf('\n');

D_loo_inv = 1 ./ D_loo;
D_loo_inv(D_loo < 1e-15) = 0;
R_loo = diag(D_loo_inv) * Cov_p_loo * diag(D_loo_inv);
R_loo = min(max(R_loo, -1), 1);
R_loo = (R_loo + R_loo') / 2;
R_loo(1:n_params+1:end) = 1;

offDiag = R_loo(~eye(n_params, 'logical'));
fprintf('   - LOO correlation matrix (off-diagonal range [%.3f, %.3f])\n', ...
    min(offDiag), max(offDiag));

Cov_p_hyb = diag(D_fim) * R_loo * diag(D_fim);
Cov_p_hyb = (Cov_p_hyb + Cov_p_hyb') / 2;
[V, E] = eig(Cov_p_hyb);
e = diag(E);
if any(e < 0)
    fprintf('   - Warning: %d negative eigenvalue(s) in Cov_p_hyb; clamping to 0.\n', ...
        sum(e < 0));
    e(e < 0) = 0;
    Cov_p_hyb = V * diag(e) * V';
    Cov_p_hyb = (Cov_p_hyb + Cov_p_hyb') / 2;
end

fprintf('   - Hybrid marginal std devs: ');
fprintf('%.4g  ', sqrt(max(diag(Cov_p_hyb), 0))); fprintf('\n');

Var_y = zeros(m, nstates);
for i = 1:m
    St = squeeze(S(i, :, :));
    if nstates == 1, St = St(:)'; end
    Var_y(i, :) = diag(St * Cov_p_hyb * St.');
end
std_y = sqrt(max(Var_y, 0));

z = norminv(1 - alp);
UQ_lower = NaN(m, nstates);
UQ_upper = NaN(m, nstates);
UQ_lower(1, :) = initial_values_all_states;
UQ_upper(1, :) = initial_values_all_states;

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

fprintf('Hybrid UQ complete: FIM-scale + LOO-correlation (unobserved) + CUQDyn1 (observed)\n');

    function r = cost_fun_local(p, y0, tspan, ydata, obs_idx, ode_fun, dyn_fun, local_cost_opts, local_ode_opts)
        sol = call_ode(ode_fun, y0, tspan, p, dyn_fun, local_ode_opts);
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
