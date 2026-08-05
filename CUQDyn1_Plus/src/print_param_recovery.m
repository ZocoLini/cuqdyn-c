function print_param_recovery(results, true_parameters, param_names, alp)
%PRINT_PARAM_RECOVERY Print parameter estimates, intervals, and recovery flags.
%
% Works with both CUQDyn1_Plus and CUQDyn1_Plus_HybridCov output structs.
% When HybridCov results are detected (fields D_fim and Cov_p_loo present),
% the marginal std dev table also shows FIM and LOO columns for comparison.
%
% Usage:
%   print_param_recovery(results, true_parameters, param_names)
%   print_param_recovery(results, true_parameters, param_names, alp)
%
% Inputs:
%   results          CUQDyn1_Plus / CUQDyn1_Plus_HybridCov output struct.
%                    Required fields: .parameters_init, .Cov_p
%   true_parameters  [1 × n_params] true (reference) parameter values
%   param_names      {1 × n_params} cell array of parameter name strings
%   alp              Significance level (default 0.05 → 90% two-sided CI;
%                    use 0.025 for a 95% CI)
%
% This is a console reporting helper only. It does not write files or alter the
% results struct.

if nargin < 4 || isempty(alp)
    alp = 0.05;
end

n_params  = numel(true_parameters);
estimates = results.parameters_init(:)';   % ensure row vector
z_val     = norminv(1 - alp);
ci_pct    = round((1 - 2*alp) * 100);

% ── Parameter table ───────────────────────────────────────────────────────
sep = repmat('-', 1, 86);
fprintf('\n=== Parameter recovery summary (%d%% CI) ===\n', ci_pct);
fprintf('%-10s  %12s  %12s  %12s  %12s  %10s  %s\n', ...
        'Param', 'True', 'Estimate', 'CI lower', 'CI upper', 'RelErr%', 'In CI');
fprintf('%s\n', sep);

all_in_ci = true;
for p = 1:n_params
    est     = estimates(p);
    std_p   = sqrt(results.Cov_p(p, p));
    ci_lo   = est - z_val * std_p;
    ci_hi   = est + z_val * std_p;
    tru     = true_parameters(p);
    rel_err = 100 * abs(est - tru) / tru;
    in_ci   = (tru >= ci_lo) && (tru <= ci_hi);
    if ~in_ci, all_in_ci = false; end
    if in_ci, flag = 'yes'; else, flag = 'NO <--'; end
    fprintf('%-10s  %12.4g  %12.4g  %12.4g  %12.4g  %9.2f%%  %s\n', ...
            param_names{p}, tru, est, ci_lo, ci_hi, rel_err, flag);
end
fprintf('%s\n', sep);
if all_in_ci
    fprintf('All true values fall within the %d%% CI.\n', ci_pct);
else
    fprintf('WARNING: some true values lie outside the %d%% CI.\n', ci_pct);
end

% ── Marginal std devs ─────────────────────────────────────────────────────
has_hybrid = isfield(results, 'D_fim') && isfield(results, 'Cov_p_loo');
fprintf('\n=== Marginal parameter std devs ===\n');
if has_hybrid
    fprintf('%-10s  %12s  %12s  %12s\n', 'Param', 'FIM', 'LOO', 'Hybrid');
    fprintf('%s\n', repmat('-', 1, 52));
    for p = 1:n_params
        fprintf('%-10s  %12.4e  %12.4e  %12.4e\n', param_names{p}, ...
                results.D_fim(p), ...
                sqrt(results.Cov_p_loo(p, p)), ...
                sqrt(results.Cov_p(p, p)));
    end
else
    fprintf('%-10s  %12s\n', 'Param', 'Std dev');
    fprintf('%s\n', repmat('-', 1, 26));
    for p = 1:n_params
        fprintf('%-10s  %12.4e\n', param_names{p}, sqrt(results.Cov_p(p, p)));
    end
end

% ── Full covariance matrix ────────────────────────────────────────────────
fprintf('\n=== Parameter covariance matrix (Cov_p) ===\n');
fprintf('%-10s', '');
for p = 1:n_params
    fprintf('  %12s', param_names{p});
end
fprintf('\n');
for p = 1:n_params
    fprintf('%-10s', param_names{p});
    for q = 1:n_params
        fprintf('  %12.4e', results.Cov_p(p, q));
    end
    fprintf('\n');
end

end
