function [UQ_lower, UQ_upper, Cov_p, std_y, fimDiagnostics] = uq_cvodes( ...
    media_tot, observed_data, observed_idx, y0, times, theta, nstates, n_params, m, ...
    UQ_lower_obs, UQ_upper_obs, alp, dynamics, cost_opts, ode_opts, fim_opts)
%UQ_CVODES The published fast_compute_hybrid_uncertainty with CVODES sensitivities.
%
% Identical to CUQDyn1_Plus/src/fast_compute_hybrid_uncertainty.m except that
% the two complex-step derivatives (the residual Jacobian J_obs and the state
% sensitivities S) come from sensitivities_cvodes. The residual weighting is a
% per-column scaling, so J_obs is the weighted sensitivity of the observed
% states, flattened like the residual vector r(:).

cost_opts = cuqdyn_fill_cost_options(cost_opts);

res_full = observed_data - media_tot(:, observed_idx);
residuals = cuqdyn_weight_residuals(res_full, cost_opts);
sigma2 = cuqdyn_residual_variance(residuals, n_params, cost_opts);

S = sensitivities_cvodes(dynamics, theta, y0, times, ode_opts);
n_obs = numel(observed_idx);
J_obs = zeros(m * n_obs, n_params);
for k = 1:n_params
    Sk = cuqdyn_weight_residuals(S(:, observed_idx, k), cost_opts);
    J_obs(:, k) = Sk(:);
end

[Cov_p, ~, fimDiagnostics, ~] = cuqdyn_fim_covariance(J_obs, sigma2, theta, S, fim_opts);

Var_y = zeros(m, nstates);
for i = 1:m
    St = squeeze(S(i, :, :));
    if nstates == 1, St = St(:)'; end
    Var_y(i, :) = diag(St * Cov_p * St.');
end
std_y = sqrt(max(Var_y, 0));

UQ_lower = NaN(m, nstates);
UQ_upper = NaN(m, nstates);
UQ_lower(1, :) = y0;
UQ_upper(1, :) = y0;
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
end
