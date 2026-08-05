function sigma2 = cuqdyn_residual_variance(weighted_residuals, n_params, cost_opts)
%CUQDYN_RESIDUAL_VARIANCE Residual variance scale for FIM covariance.

cost_opts = cuqdyn_fill_cost_options(cost_opts);
residuals = weighted_residuals(:);

if strcmpi(cost_opts.residual_model, 'known_sigma') && cost_opts.sigma_is_known
    sigma2 = 1;
else
    sigma2 = norm(residuals)^2 / max(numel(residuals) - n_params, 1);
end

end
