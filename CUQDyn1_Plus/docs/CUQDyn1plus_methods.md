# CUQDyn1_Plus Methods

This document describes the computational methods implemented in the
CUQDyn1_Plus toolbox, with emphasis on what each method estimates, the
assumptions behind it, practical strengths and limitations, and how to choose
between methods for a given ODE model.

The toolbox is designed for parameter estimation and prediction uncertainty in
ordinary differential equation models with partial state observation. A typical
problem has:

- an ODE model `dy/dt = f(t, y, theta)`;
- a parameter vector `theta`;
- observed data for one or more states;
- hidden states for which prediction bands are still needed;
- a residual/cost model that compares simulations to data.

The main MATLAB workflows are:

- `CUQDyn1_Plus`: observed-state conformal bands plus FIM delta-method bands
  for unobserved states.
- `CUQDyn1_Plus_HybridCov`: same observed-state conformal bands, but with a
  hybrid FIM/LOO parameter covariance for unobserved-state delta-method bands.
- `bootstrap_trajectory_uq`: optional post-fit parametric bootstrap trajectory
  bands.

The repository also includes `pymc_matlab/`, which provides PyMC Bayesian
posterior reference workflows for selected examples. Those scripts are useful
for comparison, but the core CUQDyn1_Plus toolbox is the MATLAB
optimization/conformal/FIM/HybridCov workflow.

## Shared Model-Fitting Core

Both `CUQDyn1_Plus` and `CUQDyn1_Plus_HybridCov` use the same fitting and
leave-one-out core, implemented in `src/private/cuq_loo_ensemble.m`.

### Full-Data Parameter Fit

The first step fits the model to all observed data by solving a bounded
least-squares problem:

```text
theta_hat = argmin_theta || r(theta) ||^2
```

where `r(theta)` is the weighted residual vector produced by the user-defined
cost function. The optimizer is MEIGO/eSS by default, with optional local
refinement through `lsqnonlin`.

The fit returns:

- `parameters_init`: the best-fit parameter vector `theta_hat`;
- `media_tot`: the full fitted ODE trajectory for all states;
- residual and diagnostic information used later by the uncertainty methods.

### Residual Models and Weighting

The residuals can be left unscaled or standardized through
`cuqdyn_weight_residuals.m`. The supported residual models are:

- `none`: raw residuals are used directly.
- `known_sigma`: residuals are divided by a known measurement standard
  deviation.
- `state_weights`: residuals are multiplied by user-specified state weights.

This weighting affects optimization, residual variance estimation, and FIM
covariance. It is important when observed states have very different physical
scales or measurement accuracies.

### Leave-One-Out Ensemble

After fitting the full dataset, the toolbox refits the model after leaving out
each non-initial observation time:

```text
theta_hat_(-i) = fit using all observed time points except time i
```

For each LOO fit, the toolbox stores:

- `loo_params`: LOO parameter estimates;
- `media_matrix`: LOO ODE trajectories;
- `resid_loo`: absolute prediction errors at the held-out data point;
- `loo_refit_diagnostics`: local/global refit diagnostics.

The LOO refits can use either global optimization or a guarded local strategy.
The local-after-global strategy is faster because it starts each LOO refit near
the full-data optimum, but it should be monitored with the stored diagnostics.

## Observed-State Conformal Prediction

Observed states use the same conformal prediction construction in both
`CUQDyn1_Plus` and `CUQDyn1_Plus_HybridCov`.

For observed state `j` and time point `i`, the toolbox combines:

- the LOO ensemble predictions at that time and state;
- the LOO held-out absolute residuals for that observed state.

The lower and upper bands are computed from empirical quantiles:

```text
lower_ij = quantile(LOO_predictions_ij - LOO_residuals_j, alpha)
upper_ij = quantile(LOO_predictions_ij + LOO_residuals_j, 1 - alpha)
```

With `alpha = 0.025`, the nominal two-sided coverage is 95%.

### Assumptions

Conformal prediction is distribution-free in the sense that it does not require
Gaussian residuals, but its validity relies on exchangeability of the observed
data/residual structure. In practice, this means the observed data should be
reasonably described by the same model and error process across the time points
used for calibration.

### Pros

- Does not require a parametric noise distribution for observed-state bands.
- Naturally captures observed-state fitting errors through held-out residuals.
- Works with nonlinear ODE models because it uses refitted trajectories rather
  than only local derivatives.
- Provides direct prediction intervals on observed states.

### Cons

- Requires many refits: roughly one full-data fit plus `m - 1` LOO fits, where
  `m` is the number of time points.
- Coverage is conditional on the usefulness of the LOO ensemble and the
  exchangeability approximation.
- Sparse time series produce coarse empirical quantiles.
- If LOO refits fail or converge to inconsistent local minima, observed-state
  bands can be unstable.

### Best Use

Use the observed-state conformal bands whenever the state is measured and the
number of observed time points is large enough to support LOO calibration. This
is the default observed-state UQ layer in the toolbox.

## FIM Delta-Method Bands

Implemented by:

- `CUQDyn1_Plus.m`
- `fast_compute_hybrid_uncertainty.m`

Despite the historical function name `fast_compute_hybrid_uncertainty`, this is
the FIM-only unobserved-state method used by `CUQDyn1_Plus`.

### Method

The method estimates a local parameter covariance matrix from a rank-aware
Fisher Information/Gauss-Newton approximation implemented in
`cuqdyn_fim_covariance`.

```text
J_fim = J_nat * diag(theta_hat)       when opts.fim.parameterization = "log"
Cov_fim ~= sigma2 * inv(J_fim' * J_fim + lambda_rel * smax^2 * I)
```

where:

- `J_nat` is the Jacobian of weighted residuals with respect to natural
  parameters;
- `J_fim` is the Jacobian in the configured FIM parameterization;
- `sigma2` is the residual variance scale;
- `lambda_rel` is `opts.fim.relative_ridge`, applied relative to the squared
  largest singular value of `J_fim`.

By default, `opts.fim.parameterization = "log"` and
`opts.fim.covariance_method = "relative_ridge"`. The covariance returned to
callers as `Cov_p` is always transformed back to natural parameter units so
existing reports, confidence intervals, and delta-method propagation remain in
the same units as the fitted parameters.

Rank and conditioning diagnostics are computed from an SVD of `J_fim`, not from
an eigendecomposition of `J'J`. The helper stores singular values, detected
rank, condition number, weak-direction indices, ridge size, parameterization,
and covariance method in `results.diagnostics.fim`.

When the FIM is rank deficient or nearly so, every scalar regularizer is a
modeling choice rather than a uniquely correct covariance. The toolbox therefore
also computes normalized weak-direction sensitivity fractions in
`results.diagnostics.fim_reliability`; states whose bands project strongly onto
weak FIM directions are flagged as unreliable.

The toolbox computes `J` by complex-step differentiation, which is usually more
accurate than finite differences for smooth models.

For each time point, state prediction uncertainty is propagated with the delta
method:

```text
S(t) = d y(t, theta) / d theta
Var[y(t)] = S(t) * Cov_FIM * S(t)'
```

where `S(t)` is the trajectory sensitivity matrix, also computed by complex-step
ODE solves.

For unobserved states, prediction bands are:

```text
y_hat(t) +/- z_(1-alpha) * sqrt(Var[y(t)])
```

Observed states still use conformal bands; FIM bands are used only for
unobserved states in the combined `CUQDyn1_Plus` output.

### Assumptions

- The fitted optimum is locally informative and approximately unique.
- The residual model and weighting are appropriate.
- The residual surface is approximately quadratic near `theta_hat`.
- Trajectory predictions are approximately linear in parameters near
  `theta_hat`.
- Parameter uncertainty is reasonably approximated by a Gaussian distribution.

### Pros

- Fast after the LOO core has completed.
- Uses a standard, interpretable local covariance approximation.
- Scales better than bootstrap or full Bayesian sampling for moderate parameter
  dimensions.
- Works well when parameters are identifiable and the model is locally smooth.
- Provides diagnostic covariance and marginal standard deviations.

### Cons

- Can under-cover when the model is strongly nonlinear, weakly identifiable, or
  has curved/ridged likelihood geometry.
- Sensitive to residual scaling, weak identifiability, and the chosen
  regularization for near-singular FIMs.
- Gaussian symmetric bands may be inappropriate for strictly positive states or
  skewed prediction uncertainty.
- Does not capture multi-modal parameter uncertainty.
- Local linearization can fail for chaotic, stiff, discontinuous, or
  event-driven dynamics.

### Best Use

Use `CUQDyn1_Plus` as the first-line method for small-to-medium smooth ODE
models when:

- the fit is stable;
- the number of parameters is not too large;
- the hidden-state uncertainty is expected to be locally Gaussian;
- runtime matters;
- you want a simple and reproducible baseline.

## HybridCov Delta-Method Bands

Implemented by:

- `CUQDyn1_Plus_HybridCov.m`
- `hybrid_empirCov.m`

### Method

HybridCov uses the same conformal observed-state bands as `CUQDyn1_Plus`.
For unobserved states, it still uses delta-method propagation, but it changes
the parameter covariance matrix.

The covariance is decomposed into marginal scale and correlation:

```text
Cov = D * R * D
```

HybridCov uses:

```text
Cov_hyb = D_FIM * R_LOO * D_FIM
```

where:

- `D_FIM` is the diagonal matrix of FIM marginal parameter standard deviations
  from the same rank-aware FIM helper used by `CUQDyn1_Plus`;
- `R_LOO` is the parameter correlation matrix estimated from `loo_params`.

The motivation is that the FIM often gives a reasonable variance scale, while
the LOO ensemble can provide an empirical correlation structure. The LOO
covariance alone is not used as the final covariance scale because LOO parameter
spread can be much smaller than true repeated-sample parameter uncertainty.

After assembling `Cov_hyb`, the toolbox propagates it to state trajectories
using the same sensitivity/delta-method formula as the FIM method.

### Assumptions

HybridCov inherits the local linear/Gaussian assumptions of the delta method,
but replaces the pure FIM correlation structure with empirical LOO correlation.
It also assumes the LOO refits are stable enough to estimate a meaningful
parameter correlation matrix.

### Pros

- Often improves hidden-state coverage when FIM marginal scales are good but
  FIM correlations are questionable.
- Costs little extra beyond `CUQDyn1_Plus`, because the LOO parameters are
  already computed.
- Stores useful diagnostics:
  - `Cov_p_fim`;
  - `Cov_log`;
  - `Cov_p_loo`;
  - `R_loo`;
  - `D_fim`;
  - `results.diagnostics.fim`;
  - `results.diagnostics.fim_reliability`.
- Uses the same interface as `CUQDyn1_Plus`, so scripts can switch methods by
  changing the function name.

### Cons

- Still a local delta-method approximation.
- LOO correlations can be noisy when there are few time points or many
  parameters.
- If LOO refits are unstable or hit bounds, the empirical correlation matrix can
  become misleading.
- It is not distribution-free for unobserved states.
- It should be calibrated by SBC or repeated synthetic tests for each model
  family.

### Best Use

Use `CUQDyn1_Plus_HybridCov` when:

- hidden-state UQ matters more than pure speed;
- the model has correlated parameters;
- FIM-only bands look too narrow or too sensitive to parameter correlation;
- there are enough time points for the LOO correlation matrix to be meaningful;
- SBC or simulation checks are available.

For many practical examples, HybridCov is a useful comparison method against
the FIM baseline, but it should not be treated as automatically more
conservative or better calibrated. Inspect FIM reliability diagnostics and use
SBC or repeated synthetic checks when coverage claims matter.

## Parametric Bootstrap Trajectory Bands

Implemented by:

- `bootstrap_trajectory_uq.m`

### Method

The bootstrap method starts from an existing `CUQDyn1_Plus` or
`CUQDyn1_Plus_HybridCov` result. It:

1. estimates observed-state noise from residuals around the fitted trajectory;
2. simulates bootstrap observed datasets around the fitted trajectory;
3. refits parameters for each bootstrap dataset;
4. solves the ODE for each refitted parameter vector;
5. forms empirical quantile bands across bootstrap trajectories.

The output is a trajectory ensemble and empirical lower/upper bands.

### Interpretation

These are latent trajectory uncertainty bands, not noisy-observation prediction
intervals. They are best interpreted as uncertainty in the fitted deterministic
ODE trajectory induced by parameter uncertainty and the assumed bootstrap noise
model.

### Assumptions

- The fitted trajectory is a reasonable data-generating center.
- The residual-based noise estimate is appropriate for generating bootstrap
  datasets.
- The optimizer can refit each bootstrap dataset reliably.
- The number of bootstrap replicates is large enough for stable quantiles.

### Pros

- Less dependent on local linearization than FIM or HybridCov.
- Can capture some nonlinear and asymmetric trajectory uncertainty.
- Produces an empirical trajectory ensemble that is easy to inspect.
- Useful as a robustness check against delta-method bands.

### Cons

- Much slower because it performs many complete refits.
- Depends on the assumed bootstrap noise model.
- Can fail or become expensive for stiff, high-dimensional, or hard-to-fit
  models.
- Does not automatically solve identifiability or multi-modality problems if
  the optimizer repeatedly returns the same local mode.
- Quantiles can be noisy unless many bootstrap replicates are used.

### Best Use

Use bootstrap when:

- the model is small or moderate;
- runtime is acceptable;
- nonlinear trajectory uncertainty is a concern;
- you want an empirical check on FIM/HybridCov;
- you can afford tens to hundreds of additional refits.

Avoid bootstrap as the default for very large, slow, stiff, or poorly
identifiable models unless you have a carefully controlled refit strategy.

## SBC Calibration Scripts

Several examples include simulation-based calibration (SBC) scripts. These are
not end-user prediction methods, but they are essential validation tools.

An SBC script typically:

1. generates many synthetic datasets from known parameters;
2. runs one or more UQ methods on each dataset;
3. checks whether the resulting bands cover the known true trajectories;
4. reports pointwise coverage, simultaneous coverage, and band width.

Shared-fit SBC scripts compare FIM and HybridCov from the same optimizer
solution, LOO ensemble, residual variance, and sensitivity linearization. This
isolates the covariance construction from stochastic optimizer differences.

Fast SBC variants use guarded `local_after_global` LOO refits after the initial
global fit. This can reduce runtime substantially, but diagnostics should be
checked for local failures, bound hits, and large parameter moves.

### Best Use

Use SBC when developing a new model or choosing between FIM, HybridCov, and
bootstrap. It is the most direct way to check empirical coverage for a model
family and data-generating regime.

## PyMC Bayesian Reference Workflows

The `pymc_matlab/` folder contains MATLAB wrappers and Python/PyMC scripts for
Bayesian inference on selected examples. These workflows provide an independent
posterior reference for comparison with CUQDyn1_Plus.

### Method

The PyMC scripts define priors and ABC distance/error models, then sample from
the posterior distribution of model parameters. Posterior parameter samples are
propagated through the ODE to produce trajectory ensembles and prediction
summaries. The maintained comparison scripts export 500 trajectory samples per
state. Observed-state exports include RMSE-based observation-noise augmentation
for posterior predictive coverage checks, while `*_latent_trajectories.csv`
files preserve the parameter-uncertainty-only trajectories.

### Pros

- Provides a full posterior distribution, not only local covariance.
- Can represent skewness, nonlinear uncertainty, and prior information.
- Useful as an independent benchmark for CUQDyn1_Plus bands.

### Cons

- Requires a Python/PyMC environment.
- Usually much slower than FIM or HybridCov.
- Requires careful prior and likelihood choices.
- Sampling diagnostics must be checked.
- ABC tolerances, distance normalization, and trajectory-noise exports affect
  direct comparison with CUQDyn bands.
- Currently provided as reference workflows for selected examples rather than
  as the main MATLAB toolbox API.

### Best Use

Use PyMC workflows when:

- you need a Bayesian reference or posterior uncertainty;
- prior information is important;
- the model is small enough for repeated Bayesian ODE solves;
- you want to compare optimization-based intervals with posterior intervals.

For direct CUQDyn-versus-PyMC comparisons, run
`pymc_matlab/compare_cuqdyn_pymc.m` after both sets of workflows have completed.
It writes shared parameter summaries, trajectory-band summaries, and
side-by-side predictive figures. The report generator
`scripts/generate_cuqdyn_pymc_comparison_report.py` converts the latest
comparison outputs into a LaTeX report.

## Method Selection Guide

### Quick Recommendation Table

| Model/data situation | Recommended starting point | Reason |
| --- | --- | --- |
| Smooth ODE, few to moderate parameters, stable fit | `CUQDyn1_Plus` | Fast, interpretable FIM baseline |
| Hidden states are central and parameters are correlated | `CUQDyn1_Plus` plus `CUQDyn1_Plus_HybridCov` comparison | Compares pure FIM and empirical LOO correlation with the same FIM scale |
| Strong nonlinear effects but model is still cheap to refit | FIM/HybridCov plus `bootstrap_trajectory_uq` | Bootstrap checks local linear bands |
| Very sparse time series | FIM baseline plus cautious diagnostics | LOO quantiles and LOO correlations are coarse |
| Many parameters relative to data | FIM/HybridCov only with strong diagnostics/SBC | FIM and LOO correlations can be ill-conditioned; weak-direction reliability flags are essential |
| Stiff or expensive ODE | Start with FIM; reduce LOO/refit cost carefully | Bootstrap may be too expensive |
| States have very different magnitudes | Use residual normalization before comparing methods | Otherwise the fit and FIM can be scale dominated |
| Real data with known measurement errors | Use `known_sigma` residual model | Aligns optimization and covariance with the error model |
| Real data with unknown measurement errors | Use defensible `state_weights` or sensitivity analysis | Error model assumptions drive UQ interpretation |
| Publication-grade new model | Run shared-fit SBC if synthetic truth is available | Directly evaluates coverage in the target regime |
| Need posterior rather than intervals around MLE | PyMC reference workflow | Provides Bayesian posterior uncertainty |

### Practical Decision Tree

1. Fit with `CUQDyn1_Plus`.
   - Check optimizer convergence, parameter bounds, residual plots, and
     trajectory fit.
   - If the fit is poor, fix the model, data, bounds, or residual weighting
     before interpreting UQ.

2. If hidden-state UQ matters, also run `CUQDyn1_Plus_HybridCov`.
   - Compare FIM and HybridCov band widths and parameter covariance diagnostics.
   - Inspect `R_loo`, `D_fim`, `loo_refit_diagnostics`,
     `diagnostics.fim`, and `diagnostics.fim_reliability`.

3. If FIM and HybridCov disagree strongly, run a targeted validation.
   - For synthetic settings, use SBC.
   - For real data, use sensitivity analyses over residual weights, bounds,
     initial guesses, and plausible error models.

4. If the model is cheap enough, run bootstrap as an empirical robustness check.
   - Use enough bootstrap replicates for stable quantiles.
   - Track failed refits and inspect the bootstrap parameter ensemble.

5. For complex scientific conclusions, compare with PyMC when feasible.
   - This is especially useful when priors matter, uncertainty is skewed, or
     local Gaussian assumptions are questionable.

## Model Characteristics That Matter

### Number of Parameters

Small parameter dimension is favorable for all methods. As parameter dimension
increases:

- the FIM matrix becomes more prone to ill-conditioning;
- LOO correlations require more data to estimate reliably;
- bootstrap refits become more expensive;
- Bayesian sampling becomes harder.

For high-dimensional models, prioritize residual scaling, identifiability
diagnostics, parameter bounds, and SBC checks.

### Number of Time Points

LOO conformal calibration and LOO correlation estimation improve with more time
points. With very few observations:

- conformal quantiles are coarse;
- `R_LOO` may be noisy;
- bootstrap and Bayesian checks become more valuable if feasible.

### Observation Pattern

If all important states are observed, conformal observed-state bands are the
main UQ output. If key states are hidden, the unobserved-state method matters
more, and FIM vs HybridCov vs bootstrap should be compared carefully.

### Identifiability

Weakly identifiable parameters often show:

- near-bound parameter estimates;
- large or unstable FIM variances;
- strong parameter correlations;
- LOO refit instability;
- very wide or very narrow suspicious bands.

No UQ method can fully compensate for a non-identifiable model. Consider
additional data, simpler parameterization, fixed parameters, or stronger prior
information.

### Dynamics and Solver Behavior

The complex-step sensitivity methods assume the ODE simulation is sufficiently
smooth with respect to parameters. Models with discontinuities, hard events,
non-smooth switches, or solver failures can break this assumption.

Stiff models can be handled, but runtime and numerical tolerances matter. Use
the stored ODE and optimizer options to make runs reproducible.

## Summary of Pros and Cons

| Method | Main output | Strengths | Limitations |
| --- | --- | --- | --- |
| Observed-state conformal | Prediction bands for measured states | Distribution-light, uses held-out errors, nonlinear trajectories allowed | Requires many refits, relies on exchangeability, coarse with few data |
| FIM delta method | Hidden-state Gaussian bands | Fast, standard, interpretable, good baseline | Local linear/Gaussian, sensitive to identifiability and scaling |
| HybridCov | Hidden-state delta bands with hybrid covariance | Empirical LOO correlations, little extra cost, useful diagnostics | Still local, LOO correlations can be noisy, needs validation |
| Bootstrap trajectory UQ | Empirical latent trajectory bands | Captures some nonlinear/asymmetric uncertainty, strong robustness check | Slow, assumes bootstrap noise model, needs many reliable refits |
| SBC scripts | Coverage validation over synthetic datasets | Direct empirical calibration, compares methods in target regime | Computationally expensive, depends on chosen synthetic regime |
| PyMC reference | Bayesian posterior trajectory uncertainty | Full posterior, priors, independent benchmark | Slow, extra Python stack, requires careful priors/diagnostics |

## Recommended Reporting

For transparent use of the toolbox, report:

- the method used: FIM, HybridCov, bootstrap, PyMC, or a comparison;
- the residual model: `none`, `known_sigma`, or `state_weights`;
- ODE solver and optimizer settings;
- FIM parameterization, covariance method, rank, condition number, number of
  weak directions, and any unreliable-band flags;
- observed and hidden states;
- number of time points and LOO refit strategy;
- optimizer warnings, bound hits, and failed refits;
- whether SBC or bootstrap checks were performed;
- whether intervals are observed-data prediction bands or latent trajectory
  bands.

This distinction is especially important because observed-state conformal bands,
hidden-state delta-method bands, bootstrap latent trajectory bands, and Bayesian
posterior predictive intervals do not answer exactly the same uncertainty
question.
