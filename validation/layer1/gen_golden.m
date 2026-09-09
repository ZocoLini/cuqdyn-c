function gen_golden(outdir)
%GEN_GOLDEN Generate golden-vector cases from the MATLAB reference.
%
%   gen_golden            writes to ./golden
%   gen_golden(outdir)    writes to outdir
%
% Each case is a directory holding plain-text inputs and the MATLAB outputs
% that the C port must reproduce. Nothing here touches MEIGO or the ODE
% solver: these kernels are pure linear algebra, so the comparison is free of
% optimiser noise. That is the whole point -- an end-to-end C-vs-MATLAB run
% would be dominated by eSS being stochastic, not by transpilation errors.
%
% Matrix file format (matches the project's data-file convention):
%   rows cols
%   <row-major values, %.17g>

if nargin < 1 || isempty(outdir)
    outdir = fullfile(fileparts(mfilename('fullpath')), 'golden');
end

here = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(here, '..', 'CUQDyn1_Plus', 'src')));

if exist(outdir, 'dir')
    rmdir(outdir, 's');
end
mkdir(outdir);

rng(20260818, 'twister');   % fixed: cases must be reproducible

manifest = {};

%% ---------------- cuqdyn_fim_covariance ----------------------------------

% 1. Small well-conditioned, log parameterization, relative_ridge (defaults).
J = [1 2; 3 4; 5 7];
manifest{end+1} = fim_case(outdir, 'fim_01_small_log', J, 1.0, [1.5; 2.5], ...
    'log', 'relative_ridge', 1e-12, 100);

% 2. Same, natural parameterization.
manifest{end+1} = fim_case(outdir, 'fim_02_small_natural', J, 1.0, [1.5; 2.5], ...
    'natural', 'relative_ridge', 1e-12, 100);

% 3. sigma2 other than 1, to check it scales the covariance linearly.
manifest{end+1} = fim_case(outdir, 'fim_03_sigma2', J, 3.7, [1.5; 2.5], ...
    'log', 'relative_ridge', 1e-12, 100);

% 4. Exactly collinear columns: rank deficient, condition number must be Inf.
%
% J'J is exactly singular here, so the only thing making it invertible is the
% ridge, 1e-12*smax^2 = 2.02e-10. That leaves cond(J'J + ridge*I) = 1.0e12, and
% inverting it amplifies rounding by eps*cond = 2.2e-4. LAPACK (MATLAB) and GSL
% (C) cannot agree to better than that no matter how faithful the port is, so
% this case gets a tolerance set from the conditioning bound rather than from
% the observed difference. Anything beyond 1e-3 here would be a real defect.
Jrd = [1 2 3; 2 4 6; 3 6 9; 1 1 2];   % col3 = col1 + col2, col2 = 2*col1
manifest{end+1} = fim_case(outdir, 'fim_04_rank_deficient', Jrd, 1.0, [1; 2; 3], ...
    'log', 'relative_ridge', 1e-12, 100, 1e-3);

% 5. Rank deficient through the SVD pseudo-inverse branch.
manifest{end+1} = fim_case(outdir, 'fim_05_svd_pinv', Jrd, 1.0, [1; 2; 3], ...
    'log', 'svd_pinv', 1e-12, 100);

% 6. Non-positive parameter: MATLAB warns and falls back to natural.
manifest{end+1} = fim_case(outdir, 'fim_06_nonpositive_theta', J, 1.0, [1.5; -0.5], ...
    'log', 'relative_ridge', 1e-12, 100);

% 7. Ill-conditioned, in the spirit of NF-kB (cond(J) ~ 1e8).
n = 40; p = 6;
Jill = randn(n, p);
[Q, ~] = qr(Jill, 0);
Jill = Q * diag(logspace(0, -8, p));
manifest{end+1} = fim_case(outdir, 'fim_07_ill_conditioned', Jill, 1.0, ...
    linspace(0.5, 3, p)', 'log', 'relative_ridge', 1e-12, 100);

% 8. Larger random problem, general numerical agreement.
Jbig = randn(120, 12) * diag(logspace(0, -3, 12));
manifest{end+1} = fim_case(outdir, 'fim_08_large', Jbig, 2.25, ...
    linspace(0.2, 5, 12)', 'log', 'relative_ridge', 1e-12, 100);

% 9. A larger relative ridge, so the regulariser is actually visible.
manifest{end+1} = fim_case(outdir, 'fim_09_big_ridge', J, 1.0, [1.5; 2.5], ...
    'log', 'relative_ridge', 1e-4, 100);

%% ---------------- hybrid covariance --------------------------------------

% Assembled inline in hybrid_empirCov.m (lines 42-72); the C factored it out
% as cuqdyn_hybrid_covariance(). Replicated here verbatim.

% 10. Ordinary LOO ensemble.
loo = bsxfun(@plus, [2.0 0.8 1.4], 0.03 * randn(30, 3));
Cfim = [0.04 0.01 0.00; 0.01 0.09 0.02; 0.00 0.02 0.16];
manifest{end+1} = hyb_case(outdir, 'hyb_01_plain', Cfim, loo);

% 11. A parameter that never moves: zero variance column exercises the
%     1e-14 diagonal bump and the divide-by-zero guard.
loo_frozen = loo;
loo_frozen(:, 2) = 0.8;
manifest{end+1} = hyb_case(outdir, 'hyb_02_frozen_param', Cfim, loo_frozen);

% 12. Strongly collinear ensemble: correlation near +-1, so the assembled
%     matrix can pick up negative eigenvalues and hit the PSD clamp.
base = randn(25, 1);
loo_col = [base, base * 0.999 + 1e-4 * randn(25, 1), base * -0.998 + 1e-4 * randn(25, 1)];
loo_col = bsxfun(@plus, [2.0 0.8 1.4], 0.02 * loo_col);
manifest{end+1} = hyb_case(outdir, 'hyb_03_collinear', Cfim, loo_col);

% 13. Only two refits, the documented minimum.
manifest{end+1} = hyb_case(outdir, 'hyb_04_two_refits', Cfim, loo(1:2, :));

%% ---------------- residual variance --------------------------------------

r = [0.5; -1.25; 0.75; 2.0; -0.5; 0.125];
manifest{end+1} = var_case(outdir, 'var_01_estimated', r, 2, 'none', false);
manifest{end+1} = var_case(outdir, 'var_02_known_sigma', r, 2, 'known_sigma', true);
manifest{end+1} = var_case(outdir, 'var_03_known_not_known', r, 2, 'known_sigma', false);
% dof clamp: numel(r) - n_params <= 0 must floor at 1
manifest{end+1} = var_case(outdir, 'var_04_dof_clamp', r, 12, 'none', false);

%% ---------------- quantile ----------------------------------------------

% matlab.c reimplements MATLAB's quantile(). The interpolation rule and the
% out-of-range clamping are easy to get subtly wrong, and the conformal
% bands depend on it directly.
qv = {[6 3 2 10 1], [6 3 2 10 8 1], [1.5 -2.25 0 7.75], [42], ...
      linspace(0, 1, 11), [3 1 4 1 5 9 2 6 5 3 5]};
qp = [0.025 0.1 0.25 0.5 0.75 0.9 0.975 0.0 1.0];
manifest{end+1} = quantile_case(outdir, 'qnt_01', qv, qp);

%% ---------------- manifest ----------------------------------------------

fid = fopen(fullfile(outdir, 'MANIFEST.txt'), 'w');
for i = 1:numel(manifest)
    fprintf(fid, '%s\n', manifest{i});
end
fclose(fid);

fprintf('Wrote %d cases to %s\n', numel(manifest), outdir);

end

% =========================================================================

function name = fim_case(outdir, name, J, sigma2, theta, param, method, ridge, rankfac, tol)
if nargin < 10, tol = []; end
d = fullfile(outdir, name);
mkdir(d);

n_params = numel(theta);
fim_opts = struct('parameterization', param, 'covariance_method', method, ...
    'relative_ridge', ridge, 'rank_tol_factor', rankfac, ...
    'weak_fraction_threshold', 0.10);

% S is only consumed by the reliability diagnostic, which the C port does not
% implement. A zero S keeps cuqdyn_fim_covariance happy and makes the omission
% explicit in the expected output below.
S = zeros(size(J, 1), 1, n_params);

warning('off', 'cuqdyn_fim_covariance:NonPositiveParameters');
warning('off', 'cuqdyn_fim_covariance:RankDeficientPinv');
[Cov_p, Cov_log, diag_, ~] = cuqdyn_fim_covariance(J, sigma2, theta, S, fim_opts);

write_matrix(fullfile(d, 'J.txt'), J);
write_matrix(fullfile(d, 'theta.txt'), theta(:));
write_kv(fullfile(d, 'opts.txt'), { ...
    'sigma2', sigma2; ...
    'parameterization', param; ...
    'covariance_method', method; ...
    'relative_ridge', ridge; ...
    'rank_tol_factor', rankfac});

write_matrix(fullfile(d, 'expect_cov_p.txt'), Cov_p);
if ~isempty(Cov_log)
    write_matrix(fullfile(d, 'expect_cov_log.txt'), Cov_log);
end
write_matrix(fullfile(d, 'expect_singular_values.txt'), diag_.singular_values(:));
write_kv(fullfile(d, 'expect_scalars.txt'), { ...
    'rank', diag_.rank; ...
    'n_weak_directions', diag_.n_weak_directions; ...
    'ridge', diag_.ridge; ...
    'condition_number', diag_.condition_number; ...
    'rank_tolerance', diag_.rank_tolerance; ...
    'sigma2', diag_.sigma2; ...
    'parameterization_used', char(diag_.parameterization)});

if ~isempty(tol)
    fid = fopen(fullfile(d, 'expect_scalars.txt'), 'a');
    fprintf(fid, 'rel_tolerance %.17g\n', tol);
    fclose(fid);
end

if isempty(tol)
    note = '';
else
    note = sprintf('  [tol=%.0e]', tol);
end
fprintf('  %-28s rank=%d cond=%.4g%s\n', name, diag_.rank, diag_.condition_number, note);
end

% -------------------------------------------------------------------------

function name = hyb_case(outdir, name, Cov_p_fim, loo_params)
d = fullfile(outdir, name);
mkdir(d);
n_params = size(Cov_p_fim, 1);

% Verbatim from hybrid_empirCov.m lines 42-72.
D_fim = sqrt(max(diag(Cov_p_fim), 0));
Cov_p_loo = cov(loo_params) + 1e-14 * eye(n_params);
D_loo = sqrt(diag(Cov_p_loo));
D_loo_inv = 1 ./ D_loo;
D_loo_inv(D_loo < 1e-15) = 0;
R_loo = diag(D_loo_inv) * Cov_p_loo * diag(D_loo_inv);
R_loo = min(max(R_loo, -1), 1);
R_loo = (R_loo + R_loo') / 2;
R_loo(1:n_params+1:end) = 1;

Cov_p_hyb = diag(D_fim) * R_loo * diag(D_fim);
Cov_p_hyb = (Cov_p_hyb + Cov_p_hyb') / 2;
[V, E] = eig(Cov_p_hyb);
e = diag(E);
n_negative = sum(e < 0);
if any(e < 0)
    e(e < 0) = 0;
    Cov_p_hyb = V * diag(e) * V';
    Cov_p_hyb = (Cov_p_hyb + Cov_p_hyb') / 2;
end

write_matrix(fullfile(d, 'cov_fim.txt'), Cov_p_fim);
write_matrix(fullfile(d, 'loo_params.txt'), loo_params);
write_matrix(fullfile(d, 'expect_cov_hyb.txt'), Cov_p_hyb);
write_matrix(fullfile(d, 'expect_r_loo.txt'), R_loo);
write_kv(fullfile(d, 'expect_scalars.txt'), {'n_negative_eigenvalues', n_negative});

fprintf('  %-28s n_neg=%d\n', name, n_negative);
end

% -------------------------------------------------------------------------

function name = var_case(outdir, name, residuals, n_params, model, sigma_known)
d = fullfile(outdir, name);
mkdir(d);
cost_opts = struct('residual_model', model, 'sigma_is_known', sigma_known, ...
    'sigma', 1.0);
sigma2 = cuqdyn_residual_variance(residuals, n_params, cost_opts);

write_matrix(fullfile(d, 'residuals.txt'), residuals(:));
write_kv(fullfile(d, 'opts.txt'), { ...
    'n_params', n_params; ...
    'residual_model', model; ...
    'sigma_is_known', double(sigma_known)});
write_kv(fullfile(d, 'expect_scalars.txt'), {'sigma2', sigma2});

fprintf('  %-28s sigma2=%.10g\n', name, sigma2);
end

% -------------------------------------------------------------------------

function name = quantile_case(outdir, name, vectors, probs)
d = fullfile(outdir, name);
mkdir(d);

fid_in = fopen(fullfile(d, 'cases.txt'), 'w');
fid_out = fopen(fullfile(d, 'expect_quantiles.txt'), 'w');
fprintf(fid_in, '%d %d\n', numel(vectors), numel(probs));
fprintf(fid_in, '%.17g ', probs); fprintf(fid_in, '\n');
for i = 1:numel(vectors)
    v = vectors{i};
    fprintf(fid_in, '%d ', numel(v));
    fprintf(fid_in, '%.17g ', v);
    fprintf(fid_in, '\n');
    for j = 1:numel(probs)
        fprintf(fid_out, '%.17g ', quantile(v, probs(j)));
    end
    fprintf(fid_out, '\n');
end
fclose(fid_in);
fclose(fid_out);

fprintf('  %-28s %d vectors x %d probs\n', name, numel(vectors), numel(probs));
end

% -------------------------------------------------------------------------

function write_matrix(path, M)
fid = fopen(path, 'w');
fprintf(fid, '%d %d\n', size(M, 1), size(M, 2));
for i = 1:size(M, 1)
    fprintf(fid, '%.17g ', M(i, :));
    fprintf(fid, '\n');
end
fclose(fid);
end

function write_kv(path, kv)
fid = fopen(path, 'w');
for i = 1:size(kv, 1)
    v = kv{i, 2};
    if ischar(v)
        fprintf(fid, '%s %s\n', kv{i, 1}, v);
    elseif isinf(v)
        fprintf(fid, '%s %s\n', kv{i, 1}, ternary(v > 0, 'inf', '-inf'));
    else
        fprintf(fid, '%s %.17g\n', kv{i, 1}, v);
    end
end
fclose(fid);
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
