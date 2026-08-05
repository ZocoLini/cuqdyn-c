function weighted = cuqdyn_weight_residuals(residuals, cost_opts)
%CUQDYN_WEIGHT_RESIDUALS Apply the selected residual error model.
%
% residuals is [n_time x n_observed_states]. For 'known_sigma',
% cost_opts.sigma must contain one standard deviation per observed state.
% For 'state_weights', cost_opts.observed_state_weights must contain one
% multiplicative weight per observed state.

cost_opts = cuqdyn_fill_cost_options(cost_opts);
model = lower(char(cost_opts.residual_model));

switch model
    case 'none'
        weighted = residuals;

    case 'known_sigma'
        sigma = cost_opts.sigma(:)';
        if isempty(sigma)
            error('cuqdyn_weight_residuals:MissingSigma', ...
                'cost_opts.sigma is required for residual_model="known_sigma".');
        end
        if numel(sigma) ~= size(residuals, 2)
            error('cuqdyn_weight_residuals:SigmaSizeMismatch', ...
                'cost_opts.sigma must have one value per observed state.');
        end
        sigma = max(abs(sigma), cost_opts.sigma_floor);
        weighted = residuals ./ sigma;

    case 'state_weights'
        weights = cost_opts.observed_state_weights(:)';
        if isempty(weights)
            error('cuqdyn_weight_residuals:MissingWeights', ...
                'cost_opts.observed_state_weights is required for residual_model="state_weights".');
        end
        if numel(weights) ~= size(residuals, 2)
            error('cuqdyn_weight_residuals:WeightSizeMismatch', ...
                'cost_opts.observed_state_weights must have one value per observed state.');
        end
        weighted = residuals .* weights;

    otherwise
        error('cuqdyn_weight_residuals:UnknownResidualModel', ...
            'Unknown residual_model: %s', model);
end

end
