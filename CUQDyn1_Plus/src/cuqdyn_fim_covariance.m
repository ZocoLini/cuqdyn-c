function [Cov_p, Cov_log, diagnostics, reliability] = cuqdyn_fim_covariance( ...
    J_nat, sigma2, parameters_init, S_nat, fim_opts)
%CUQDYN_FIM_COVARIANCE Rank-aware FIM covariance and reliability diagnostics.
%
%   Cov_p is always returned in the natural parameterization expected by
%   existing CUQDyn reporting and delta-method propagation. Diagnostics are
%   computed from an SVD of the residual Jacobian in the configured FIM
%   parameterization, which defaults to log-parameters for positive rates.

if nargin < 5 || isempty(fim_opts)
    fim_opts = struct();
end

n_params = numel(parameters_init);
fim_opts = cuqdyn_fill_fim_options(fim_opts, n_params);

theta = parameters_init(:);
useLog = strcmpi(string(fim_opts.parameterization), "log");
if useLog && any(theta <= 0)
    warning('cuqdyn_fim_covariance:NonPositiveParameters', ...
        'Non-positive parameters found; falling back to natural-parameter FIM.');
    useLog = false;
end

if useLog
    transform = theta;
    J_fim = J_nat * diag(transform);
    S_fim = local_scale_sensitivity(S_nat, transform);
    parameterization = "log";
else
    transform = ones(n_params, 1);
    J_fim = J_nat;
    S_fim = S_nat;
    parameterization = "natural";
end

[~, Ssvd, V] = svd(J_fim);
if isvector(Ssvd)
    s = Ssvd(:);
else
    s = diag(Ssvd);
end
if numel(s) > n_params
    s = s(1:n_params);
end
if numel(s) < n_params
    s(end+1:n_params, 1) = 0;
end
if isempty(s)
    smax = 0;
else
    smax = max(s(:));
end
rankTol = fim_opts.rank_tol_factor * max(size(J_fim)) * eps(max(smax, 1));
keep = s > rankTol;
weak = ~keep;
rankJ = sum(keep);

method = lower(char(fim_opts.covariance_method));
switch method
    case 'relative_ridge'
        ridge = fim_opts.relative_ridge * max(smax.^2, 1);
        A = J_fim' * J_fim + ridge * eye(n_params);
        Cov_fim = sigma2 * (A \ eye(n_params));
    case 'svd_pinv'
        if any(weak)
            warning('cuqdyn_fim_covariance:RankDeficientPinv', ...
                ['SVD pseudoinverse drops %d weak FIM direction(s); ', ...
                 'propagated uncertainty can be anti-conservative.'], sum(weak));
        end
        Cov_fim = zeros(n_params);
        if any(keep)
            Vk = V(:, keep);
            Cov_fim = sigma2 * (Vk * diag(1 ./ (s(keep).^2)) * Vk');
        end
        ridge = 0;
    otherwise
        error('cuqdyn_fim_covariance:UnknownMethod', ...
            'Unknown FIM covariance_method: %s', method);
end

Cov_fim = (Cov_fim + Cov_fim') / 2;
if useLog
    Cov_log = Cov_fim;
    Cov_p = diag(theta) * Cov_log * diag(theta);
else
    Cov_p = Cov_fim;
    Cov_log = [];
end
Cov_p = (Cov_p + Cov_p') / 2;

diagnostics = struct();
diagnostics.parameterization = parameterization;
diagnostics.covariance_method = string(method);
diagnostics.singular_values = s;
diagnostics.rank = rankJ;
diagnostics.n_params = n_params;
diagnostics.rank_tolerance = rankTol;
diagnostics.rank_tol_factor = fim_opts.rank_tol_factor;
diagnostics.relative_ridge = fim_opts.relative_ridge;
diagnostics.ridge = ridge;
diagnostics.n_weak_directions = sum(weak);
diagnostics.weak_direction_indices = find(weak);
if rankJ == 0 || smax == 0
    diagnostics.condition_number = Inf;
elseif rankJ < numel(s)
    diagnostics.condition_number = Inf;
else
    diagnostics.condition_number = smax / min(s(keep));
end
diagnostics.sigma2 = sigma2;

reliability = local_reliability(S_fim, V, weak, fim_opts.weak_fraction_threshold);
diagnostics.max_weak_fraction = reliability.maxWeakFraction;
diagnostics.any_unreliable_bands = any(reliability.bandUnreliableByState);

end

function S_scaled = local_scale_sensitivity(S, scale)
S_scaled = S;
for k = 1:numel(scale)
    S_scaled(:, :, k) = S(:, :, k) * scale(k);
end
end

function reliability = local_reliability(S, V, weak, threshold)
[m, nstates, ~] = size(S);
weakFraction = zeros(m, nstates);
if any(weak)
    Vweak = V(:, weak);
    for i = 1:m
        for j = 1:nstates
            row = squeeze(S(i, j, :))';
            denom = max(norm(row), eps);
            weakFraction(i, j) = norm(row * Vweak) / denom;
        end
    end
end

reliability = struct();
reliability.weakFraction = weakFraction;
reliability.maxWeakFractionByState = max(weakFraction, [], 1);
reliability.meanWeakFractionByState = mean(weakFraction, 1);
reliability.threshold = threshold;
reliability.bandUnreliableByState = reliability.maxWeakFractionByState > threshold;
reliability.maxWeakFraction = max(weakFraction, [], 'all');
end
