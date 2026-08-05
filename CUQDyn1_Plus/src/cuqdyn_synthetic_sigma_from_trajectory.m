function sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, noise_pct)
%CUQDYN_SYNTHETIC_SIGMA_FROM_TRAJECTORY Match bundled data-generation scripts.
%
% The synthetic generators use additive Gaussian noise with
% sigma_j = noise_pct/100 * mean(Y_true(:,j)), falling back to 1e-3 for
% near-zero mean states. Noise is added only after t=0, but the same
% state-wise sigma defines the observation-error model.

noise_fraction = noise_pct / 100;
observed_idx = observed_idx(:)';
sigma = zeros(1, numel(observed_idx));

for k = 1:numel(observed_idx)
    j = observed_idx(k);
    mean_val = mean(Y_true(:, j), 'omitnan');
    if mean_val < 1e-10
        sigma(k) = 1e-3;
    else
        sigma(k) = noise_fraction * mean_val;
    end
end

end
