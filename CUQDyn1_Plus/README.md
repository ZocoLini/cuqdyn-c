# CUQDyn1_Plus

**Hybrid Conformal–Gaussian Uncertainty Quantification for Partially Observed ODE Systems**

MATLAB R2020a+ | License: GPLv3

---

## Overview

**CUQDyn1_Plus** is a MATLAB toolbox for parameter estimation and uncertainty quantification (UQ) in ordinary differential equation (ODE) models where only a subset of state variables are experimentally observed. It addresses the common practical situation where some states are unmeasured yet reliable prediction bands are still required for them.

The toolbox implements a hybrid UQ strategy that treats observed and unobserved states differently because they admit fundamentally different statistical treatments:

| State type | Method | Basis |
|---|---|---|
| **Observed** | Conformal prediction (LOO) | Distribution-free under exchangeability/calibration assumptions |
| **Unobserved** | Delta method (Gaussian) | Linearised error propagation via FIM |

A second variant, **CUQDyn1_Plus_HybridCov**, provides an empirical alternative for unobserved states by replacing the pure FIM correlation structure with a hybrid covariance derived from the LOO parameter ensemble (see [Methodology](#methodology)). It should be interpreted together with diagnostics and, when possible, SBC checks.

CUQDyn1_Plus now supports three prediction-UQ workflows:

| Workflow | Entry point | Role |
|---|---|---|
| FIM delta-method bands | `CUQDyn1_Plus` | Fast local Gaussian propagation using FIM parameter covariance |
| HybridCov delta-method bands | `CUQDyn1_Plus_HybridCov` | Same propagation, but with FIM marginal scale and LOO-derived parameter correlation |
| Bootstrap trajectory bands | `bootstrap_trajectory_uq` | Optional post-fit empirical bands from repeated simulated-data refits |

Run settings are centralized through `cuqdyn_default_options`. The examples use
these defaults, apply any model-specific overrides, and each CUQDyn run writes a
`run_options.mat` and `run_options.xlsx` file to the result folder so optimizer
cost, optimizer, and integration settings are recorded with the output.

Simulation-based calibration (SBC) experiments are included to assess the
approximate Gaussian uncertainty used for unobserved states. Earlier separate-fit
SBC comparisons across benchmark models showed:

| Covariance for unobserved states | Mean pointwise coverage (target 95%) |
|---|---|
| FIM only | ~92% |
| LOO empirical only | ~40% |
| **Hybrid (FIM scale + LOO correlation)** | **~95%** |

A companion Bayesian ABC-SMC implementation (via PyMC) is provided for comparison across the maintained LV, SIR, AP, and NF-kB examples.

---

## Methodology

### Step 1 — Global parameter estimation

Parameters **θ** are estimated by minimising the sum of squared residuals on the observed states using **MEIGO** (enhanced scatter search, ESS) combined with the **nl2sol** local refinement algorithm. This stochastic optimiser produces robust global fits without requiring a close initial guess.

### Step 2 — Leave-one-out (LOO) ensemble

The full dataset has **m** time points. A **parfor** loop performs **m − 1** re-fits, each omitting one time point **i** ∈ {2, …, m}. This produces:

- `loo_params` — (m−1) × n_params matrix of LOO parameter vectors  
- `media_matrix` — m × n_states × (m−1) array of LOO ODE trajectories  
- `resid_loo` — absolute prediction errors at each held-out point

### Step 3 — Conformal prediction bands (observed states)

At each time point **i** and observed state **j**, the conformal interval is:

```
UQ_lower(i,j) = quantile( ens_ij − resid_loo_j ,  alp )
UQ_upper(i,j) = quantile( ens_ij + resid_loo_j ,  1−alp )
```

where `ens_ij` is the vector of LOO predictions at point **i** for state **j**, and `resid_loo_j` is the vector of LOO absolute residuals for state **j**. These bands are conformal-style, distribution-free with respect to residual shape, and are intended to provide marginal coverage **1 − 2·alp** when the exchangeability/calibration assumptions are adequate.

### Step 4 — Delta-method bands (unobserved states)

For states that are never measured, the toolbox propagates parameter uncertainty through the ODE using the **delta method** (linearised error propagation):

```
Var(y_k(t)) ≈ S_k(t) · Cov_p · S_k(t)ᵀ
```

where **S_k = ∂y_k/∂θ** is the sensitivity matrix (computed via complex-step differentiation for high accuracy) and **Cov_p** is the parameter covariance matrix. The prediction band is:

```
ŷ_k(t) ± z_{1-alp} · sqrt( Var(y_k(t)) )
```

**CUQDyn1_Plus** uses a rank-aware FIM/Gauss-Newton covariance helper. By
default, `cuqdyn_fim_covariance` builds the residual Jacobian in log-parameter
space for positive parameters, applies a scale-relative ridge regularizer,
returns `Cov_p` in natural parameter units, and stores SVD rank, conditioning,
weak-direction, and reliability diagnostics in `results.diagnostics.fim` and
`results.diagnostics.fim_reliability`.

**CUQDyn1_Plus_HybridCov** uses a hybrid covariance that decomposes into scale and correlation:

```
Cov_p_hyb = D_FIM · R_LOO · D_FIM
```

- **D_FIM** = diag of FIM marginal standard deviations from the same rank-aware covariance helper
- **R_LOO** = correlation matrix extracted from `cov(loo_params)` (data-driven correlation structure)

This combination is guaranteed positive semi-definite, but its calibration is empirical. In earlier separate-fit SBC experiments it improved coverage relative to FIM-only bands. A newer shared-fit LV calibration script (`SBC_LV2_FIM_vs_HybridCov_sharedfit.m`) compares FIM and HybridCov from the same optimiser solution and LOO ensemble; in that stricter LV setting both methods gave similar predator coverage (~93% for nominal 95%). Treat HybridCov as an empirical covariance variant whose coverage should be checked for each model rather than as a distribution-free guarantee. The LOO covariance alone gives only ~40% coverage because removing one of **m** informative points barely shifts the optimum, so `cov(loo_params)` underestimates the true estimation variance by a factor of O(m).

---

## Repository structure

```
CUQDyn1_Plus/
|
+-- src/                              Core toolbox functions
|   +-- CUQDyn1_Plus.m                Main entry point (FIM covariance)
|   +-- CUQDyn1_Plus_HybridCov.m      Hybrid FIM/LOO covariance variant
|   +-- hybrid_empirCov.m             Hybrid covariance assembly + delta method
|   +-- fast_compute_hybrid_uncertainty.m  FIM-only delta method
|   +-- bootstrap_trajectory_uq.m     Optional parametric bootstrap trajectory UQ
|   +-- cuqdyn_default_options.m      Central optimizer/UQ/ODE defaults
|   +-- cuqdyn_fill_cost_options.m    Fill residual weighting defaults
|   +-- cuqdyn_fill_fim_options.m     Fill FIM covariance defaults
|   +-- cuqdyn_fill_meigo_options.m   Fill optimizer defaults
|   +-- cuqdyn_fill_refit_options.m   Fill repeated-refit defaults
|   +-- cuqdyn_fim_covariance.m       Rank-aware FIM covariance and diagnostics
|   +-- cuqdyn_set_ode_options.m      Set shared ODE integration options
|   +-- cuqdyn_get_ode_options.m      Read shared ODE integration options
|   +-- cuqdyn_odeset_from_options.m  Convert ODE option structs to odeset
|   +-- cuqdyn_weight_residuals.m     Residual weighting for cost functions/FIM
|   +-- cuqdyn_cost_options_from_problem.m  Build cost_opts from problem definitions
|   +-- cuqdyn_residual_variance.m    FIM variance scale for weighted residuals
|   +-- cuqdyn_synthetic_sigma_from_trajectory.m  Synthetic-data sigma helper
|   +-- cuqdyn_validate_problem.m     Validate high-level problem definitions
|   +-- cuqdyn_generate_problem_files.m  Generate legacy dynamics/cost modules
|   +-- cuqdyn_generate_synthetic_data.m  Generate CUQDyn CSV data
|   +-- cuqdyn_generate_data_script.m Generate readable synthetic-data scripts
|   +-- cuqdyn_check_generated_problem_modules.m  Compare generated modules to legacy files
|   +-- save_run_options.m            Print and save effective run options
|   +-- diagnose_uq_quality.m         Post-fit UQ diagnostics
|   +-- plot_hybrid_uq.m              Prediction band plot (all states)
|   +-- print_param_recovery.m        Parameter recovery summary table
|   +-- save_trajectory_nrmse_tables.m  Trajectory error and UQ coverage tables
|   +-- savefig_png.m                 Crash-safe figure saver (.fig/.png/.pdf/.eps)
|   +-- save_results_to_excel.m       Compact Excel export
|   +-- save_results_to_excel_detailed.m  Annotated Excel export
|   +-- loadStateData.m               CSV data loader
|   +-- ODE_solve.m                   ODE integrator wrapper
|   +-- prob_mod_cost_Generic.m       Generic cost function template
|   +-- private/
|       +-- cuq_loo_ensemble.m        LOO fit + conformal bounds (shared core)
|       +-- cuq_fit_repeated_problem.m  Global/local repeated-fit helper
|       +-- cuq_parpool.m             Parallel pool manager
|       +-- jacobianest_cs.m          Complex-step Jacobian
|
+-- EXAMPLES/
|   +-- Master_Run_Results_*/         Output folders from run_all_examples.m
|   +-- problem_definition_template.m Copyable problem-definition cheatsheet
|   +-- check_generated_problem_definitions.m Verify generated modules against legacy examples
|   |
|   +-- LinearCascade/                Analytic two- and three-state linear UQ checks
|   |   +-- METHOD_NOTES.md
|   |   +-- define_problem_LinearCascade.m
|   |   +-- define_problem_LinearCascade3.m
|   |   +-- diagnose_LinearCascade_known_truth.m
|   |   +-- diagnose_LinearCascade3_known_truth.m
|   |   +-- SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit.m
|   |   +-- SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit_fast.m
|   |   +-- prob_mod_dynamics_LinearCascade.m
|   |   +-- prob_mod_cost_LinearCascade.m
|   |   +-- prob_mod_dynamics_LinearCascade3.m
|   |   +-- prob_mod_cost_LinearCascade3.m
|   |   +-- data/
|   |   +-- data_generation/
|   |
|   +-- LV/                           Lotka-Volterra predator-prey
|   |   +-- METHOD_NOTES.md
|   |   +-- define_problem_LV.m
|   |   +-- check_generated_LV_problem.m
|   |   +-- run_LV2_CUQDyn1_Plus_partobs_example.m
|   |   +-- run_LV2_CUQDyn1_Plus_HybridCov_partobs_example.m
|   |   +-- tutorial_LV_three_prediction_UQ_methods.m
|   |   +-- SBC_LV2_FIM_vs_HybridCov.m
|   |   +-- SBC_LV2_FIM_vs_HybridCov_fast.m
|   |   +-- SBC_LV2_FIM_vs_HybridCov_sharedfit.m
|   |   +-- SBC_LV2_FIM_vs_HybridCov_sharedfit_fast.m
|   |   +-- prob_mod_dynamics_LV.m
|   |   +-- prob_mod_cost_LV.m
|   |   +-- data/
|   |   +-- data_generation/
|   |
|   +-- SIR/                          Epidemic SIR model
|   |   +-- METHOD_NOTES.md
|   |   +-- define_problem_SIR.m
|   |   +-- run_SIR_CUQDyn1Plus.m
|   |   +-- run_SIR_CUQDyn1Plus_HybridCov.m
|   |   +-- SBC_SIR_FIM_vs_HybridCov.m
|   |   +-- SBC_SIR_FIM_vs_HybridCov_fast.m
|   |   +-- prob_mod_dynamics_SIR.m
|   |   +-- prob_mod_cost_SIR.m
|   |   +-- data/
|   |   +-- data_generation/
|   |
|   +-- AP/                           Alpha-pinene isomerization
|   |   +-- METHOD_NOTES.md
|   |   +-- define_problem_AP.m
|   |   +-- run_AP_CUQDyn1Plus_partobs_example.m
|   |   +-- run_AP_CUQDyn1Plus_HybridCov_partobs_example.m
|   |   +-- SBC_AP_FIM_vs_HybridCov.m
|   |   +-- SBC_AP_FIM_vs_HybridCov_fast.m
|   |   +-- prob_mod_dynamics_AP.m
|   |   +-- prob_mod_cost_AP.m
|   |   +-- data/
|   |   +-- data_generation/
|   |
|   +-- NFKB/                         NF-kB signaling example
|       +-- METHOD_NOTES.md
|       +-- define_problem_NFKB.m
|       +-- run_NFKB_example_CUQDyn1plus.m
|       +-- run_NFKB_example_CUQDyn1plus_HybCov.m
|       +-- run_NFKB_example.m         Legacy diagnostic runner
|       +-- prob_mod_dynamics_NFKB.m
|       +-- prob_mod_cost_NFKB.m
|       +-- data/
|       +-- data_generation/
|
+-- docs/                              Documentation
|   +-- CUQDyn1plus_methods.md
|   +-- tutorialUQ.md
|   +-- tutorialProblemDef.md
|   +-- README_run_all_examples.md
|
+-- pymc_matlab/                       Bayesian ABC-SMC comparison (Python/PyMC)
|   +-- lv_pymc.py
|   +-- sir_pymc.py
|   +-- ap_pymc.py
|   +-- nfkb_pymc.py
|   +-- pymc_export_utils.py
|   +-- compare_cuqdyn_pymc.m
|   +-- pyMC_settings.md
|   +-- pyMC_windows_install.md
|   +-- run_bayes_*.m                  MATLAB wrappers for Python runs
|   +-- results/                       Generated output CSVs and plots
|
+-- unitTests/
|   +-- test_CUQDyn1Plus.m
|   +-- test_plotting_functions.m
|   +-- test_trajectory_nrmse_tables.m
|   +-- test_diagnose_uq_quality.m
|   +-- test_bootstrap_trajectory_uq.m
|   +-- test_problem_definition_generator.m
|   +-- test_cuqdyn_fim_covariance.m
|   +-- test_cuqdyn_options.m
|
+-- scripts/                           Auxiliary report generators and batch utilities
|   +-- run_full_evaluation.m          End-to-end manuscript pipeline batch runner
|   +-- run_sbc_evaluation.m           MATLAB SBC calibration batch runner
|   +-- generate_results_latex_report.py
|   +-- generate_cuqdyn_pymc_comparison_report.py
|   +-- generate_combined_tutorial_latex.py
|   +-- how_to_generate_figures_tables.md
+-- CHANGELOG.md
+-- LICENSE                            GPLv3 license text
+-- run_all_examples.m                 Master non-SBC example-suite runner
+-- validate_cuqdyn_repo.m             Lightweight local/CI validation script
+-- README.md
```
`run_all_examples.m` and `validate_cuqdyn_repo.m` are intentionally kept at the
repository root as user-facing entry point scripts. The `scripts/` folder is
reserved for auxiliary report generators, batch utilities, and other supporting
automation.

---

## Dependencies

| Dependency | Notes |
|---|---|
| MATLAB R2020a or later | `exportgraphics` required for figure saving |
| Statistics and Machine Learning Toolbox | `norminv`, `quantile` |
| Optimization Toolbox | `lsqnonlin` (local refinement inside MEIGO) |
| Parallel Computing Toolbox | Optional but strongly recommended for LOO loop |
| MEIGO64 | Required for optimisation examples; available at [gingproc-IIM-CSIC/MEIGO64](https://github.com/gingproc-IIM-CSIC/MEIGO64). Set `MEIGO64_PATH` or place `MEIGO64-master/` at the repo root |

Python dependencies are only needed if you want to compare CUQDyn1_Plus with
UQ via Bayesian inference. Those scripts use `pymc`
([https://www.pymc.io/](https://www.pymc.io/)), `arviz`, `scipy`, `numpy`,
`pandas`, and `matplotlib`.
Windows users should follow `pymc_matlab/pyMC_windows_install.md`, which covers
`uv`, VS Code Python support, MSYS2, and the GCC/G++ toolchain used by PyTensor.

---

## Installation

```matlab
% From the repo root, add everything to the MATLAB path:
addpath(genpath('path/to/CUQDyn1_Plus'));
```

Or run from within any example directory — each script begins with `addpath(genpath('../../'))`.

---

## Data format

Data must be a CSV file with the following layout:

```
time, y1, y2, ..., yn
0,    ic1, ic2, ..., icn       ← initial conditions for ALL states (no NaN)
t1,   v1,  NaN, ..., vn        ← NaN for unobserved states after t=0
t2,   v1,  NaN, ..., vn
...
```

- Column 1: time points (strictly increasing)  
- Columns 2+: state values; unobserved states are `NaN` at all times after t = 0  
- Row 1 (t = 0) must contain valid initial conditions for every state

**Example** (Lotka-Volterra, prey observed, predator unobserved):

```
time, y1,    y2
0,    10.0,  5.0
1,    9.43,  NaN
2,    8.62,  NaN
...
```

Use `loadStateData(dataDir, filename, nstates)` to read this format:

```matlab
[times, all_state_data, ic, observed_data, observed_idx] = ...
    loadStateData('data', 'mydata.csv', nstates);
```

---

## Generating synthetic data

Each example that uses synthetic observations has a canonical generator in
`EXAMPLES/<example>/data_generation/`. These scripts write CSV files into the
corresponding `EXAMPLES/<example>/data/` folder, which is the folder read by the
run scripts. Generated CSVs inside `data_generation/` are ignored so the
generator folder stays script-only.

```matlab
cd EXAMPLES/LV/data_generation
generateSyntheticData_LV

cd ../../SIR/data_generation
generateSyntheticData_SIR

cd ../../AP/data_generation
generateSyntheticData_AP

cd ../../NFKB/data_generation
generateSyntheticData_NFKB

cd ../../LinearCascade/data_generation
generateSyntheticData_LinearCascade
```

All generators use the same convention:

- edit the **User control panel** at the top of the script;
- set `time_points`, `true_parameters`, `initial_conditions`, `is_observed`,
  `noise_level_percent`, `rng_seed`, `min_observed_value`, and
  `output_filename`;
- keep `is_observed(j) = 0` for hidden states; the generated CSV keeps their
  initial condition at `t=0` and writes `NaN` afterward;
- observed states receive additive Gaussian noise only after `t=0`, with
  `sigma_j = noise_level_percent/100 * mean(Y_true(:,j))`, matching
  `cuqdyn_synthetic_sigma_from_trajectory`;
- finite generated values are checked to be nonnegative; negative noisy
  observed values after `t=0` are floored at `min_observed_value`;
- the default `min_observed_value = 0` preserves physically exact zero initial
  conditions in examples such as AP, SIR, NF-kB, and LinearCascade. If an
  application requires strictly positive observed measurements after `t=0`, set
  `min_observed_value` to a small positive value before regenerating the CSV;
- when using these synthetic datasets in examples, prefer
  `opts.cost.residual_model = 'known_sigma'` and pass the same sigma values
  through `opts.cost.sigma`.

**Positivity note.** The built-in models represent concentrations, populations,
or abundances, so generated finite data should never be negative. The generators
therefore validate nonnegativity and floor noisy observed values after `t=0`.
They do **not** force every finite value to be strictly positive by default,
because several examples have exact zero initial conditions that are part of the
model definition. Use a small positive `min_observed_value` only when your
measurement model requires strictly positive observed data after the initial
condition.

The bundled CSV files used by the examples in each `data/` folder have been
checked for this convention: they contain no negative finite values. Their
minimum finite value is `0`, reflecting exact initial conditions or physically
zero states rather than invalid negative measurements.

The bundled run scripts intentionally read existing CSV files rather than
generating data inline. This keeps estimation runs reproducible: regenerate or
replace the CSV first, then run the CUQDyn example script. The AP run scripts use
experimental alpha-pinene measurements by default; to fit AP synthetic data,
change `data_file_name` in the AP run script to the generated synthetic CSV.

Older AP/LV nested generator entry points are kept as wrappers for
compatibility, but new work should use the canonical scripts listed above.

---

## Running the built-in examples

All examples follow the same pattern. Run from the example directory or add the repo root to the path first.

Each maintained example folder includes a short `METHOD_NOTES.md` file that
records why its observed-state choice, residual scaling, parameter bounds, and
selected UQ workflows are appropriate for that model.

To run the full non-SBC example suite as an integration check, use the master
runner from the repository root:

```matlab
summary = run_all_examples();
summary = run_all_examples('StopOnFailure', true);
```

The runner executes the LV, SIR, AP, NFKB, and LinearCascade examples with
their available CUQDyn methods, but intentionally skips all SBC scripts. Each
example is run from its own folder, errors are caught per script, result MAT
files and core result fields are sanity checked, and a summary workbook/CSV plus
per-example logs are written to `EXAMPLES/Master_Run_Results_<timestamp>/`.
This is intended as a smoke/integration test; it can still take a long time
because it runs the actual optimizer-based examples.

For a much faster pre-push health check that does not run MEIGO, the examples,
or SBC scripts, use:

```matlab
summary = validate_cuqdyn_repo();
```

This lightweight validator checks path setup, selected Code Analyzer messages,
problem-definition validity, CSV observability metadata, generated-module
equivalence, and a tiny generated LV data/cost smoke test.

The recommended settings pattern is:

```matlab
opts = cuqdyn_default_options(n_params);
opts.uq.alp = alp;

% Optional model-specific overrides
opts.meigo.maxeval = n_params * 1000;
opts.ode.RelTol = 1e-8;
opts.ode.AbsTol = 1e-10;

% Optional experimental speed-up for LOO repeated fits
opts.meigo.refit.strategy = 'local_after_global';

% Optional, statistically preferred for synthetic data with known noise SDs
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = sigma_observed_states;
opts.cost.sigma_is_known = true;

cuqdyn_set_ode_options(opts.ode);
meigo_opts = opts.meigo;
meigo_opts.cost_opts = opts.cost;

results = CUQDyn1_Plus(..., resultDir, meigo_opts);
```

By default, `opts.meigo.maxeval = n_params * 500` and repeated LOO fits use the
original eSS global optimiser (`opts.meigo.refit.strategy = 'global'`). Users
can override any field in the run script. The effective MEIGO, refit, ODE, and
UQ options are printed and saved in the result directory.

For faster comparative testing, the temporary guarded local-refit mode uses eSS
for the first full-data fit, then uses `lsqnonlin` initialized at that solution
for each LOO refit:

```matlab
opts.meigo.refit.strategy = 'local_after_global';
opts.meigo.refit.retry_global_on_failure = true;
opts.meigo.refit.max_cost_ratio_from_start = 1.01;
opts.meigo.refit.max_parameter_fold_change = 10;
```

If a local refit fails, worsens the objective relative to the full-fit seed, or
moves implausibly far in parameter space, the replicate is retried with eSS. The
per-LOO diagnostics are saved in `results.loo_refit_diagnostics`, so this mode
can be compared against the current eSS-everywhere behavior before changing
toolbox defaults.

For synthetic benchmark data, the statistically coherent cost is weighted least
squares using the same observation-error standard deviations used to generate
the data. The bundled synthetic examples set:

```matlab
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = ...      % one sigma per observed state
```

Then both optimisation and FIM covariance use standardized residuals. Raw
RMSE/MAE/NRMSE are still reported separately in physical units.

### Lotka-Volterra (2 states, 4 parameters)

Prey (`y1`) observed at 31 time points; predator (`y2`) unobserved. True parameters: α = 0.5, β = 0.02, δ = 0.02, γ = 0.5. Synthetic data with 10% proportional noise.

```matlab
cd EXAMPLES/LV
run_LV2_CUQDyn1_Plus_partobs_example          % FIM covariance
run_LV2_CUQDyn1_Plus_HybridCov_partobs_example % Hybrid covariance
tutorial_LV_three_prediction_UQ_methods       % FIM, HybridCov, bootstrap comparison
SBC_LV2_FIM_vs_HybridCov_sharedfit            % eSS LOO refits
SBC_LV2_FIM_vs_HybridCov_sharedfit_fast       % guarded local LOO refits
```

The LV tutorial is the cheapest end-to-end demonstration of the three UQ workflows. A written walkthrough is available in `docs/tutorialUQ.md`. The script runs FIM and HybridCov with reduced MEIGO settings, then runs a bootstrap from the FIM fit. It writes per-method metric workbooks plus `three_uq_methods_metric_comparison.xlsx`, with one sheet for observed-data fit metrics and one sheet for latent true-trajectory coverage. This distinction matters because bootstrap trajectory bands are latent ODE-trajectory bands, not noisy-observation prediction intervals.

### LinearCascade known-truth diagnostic (2 states, 2 parameters)

A small analytic test case for checking numerical consistency of weighted
least-squares fitting, FIM covariance, and hidden-state delta-method
uncertainty. Only state `x2` is observed; state `x1` is hidden. The script uses
the analytic trajectory solution to build an independent covariance reference.

```matlab
cd EXAMPLES/LinearCascade
diagnose_LinearCascade_known_truth
```

The output workbook `linear_cascade_numerics_summary.xlsx` compares CUQDyn's
parameter covariance and hidden-state standard deviations against the analytic
reference calculation.

### LinearCascade3 known-truth diagnostic (3 states, 3 parameters)

LinearCascade3 is a more demanding linear cascade diagnostic. It observes only
the downstream state `x3`, leaving upstream states `x1` and `x2` hidden. This
makes it a compact hidden-state uncertainty stress test for checking whether the
FIM and HybridCov machinery behaves sensibly when the measured signal is
indirectly related to the hidden dynamics.

```matlab
cd EXAMPLES/LinearCascade
diagnose_LinearCascade3_known_truth
```

This script compares CUQDyn against an independent matrix-exponential reference
and writes `linear_cascade3_numerics_summary.xlsx`. It is also included in
`run_all_examples.m` as `LinearCascade3`.

For repeated-simulation calibration of the three-state cascade:

```matlab
cd EXAMPLES/LinearCascade
SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit
SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit_fast
```

This script compares FIM and HybridCov hidden-state coverage from the same fit
per replicate. The `_fast` variant uses `opts.meigo.refit.strategy =
'local_after_global'` for LOO refits while keeping the first fit global. It is
intended for side-by-side runtime and calibration comparisons against the
eSS-everywhere baseline. The current LinearCascade3 shared-fit scripts default
to larger calibration batches than the original smoke checks; edit
`default_sharedfit_config()` at the bottom of the script for quick smoke tests
or larger calibration studies.

### SIR epidemic model (3 states, 2 parameters)

Infected (`y2`) observed at 31 time points; Susceptible and Recovered unobserved. True parameters: β = 0.002, γ = 0.5. The CUQDyn scripts read the pre-generated synthetic CSV in `EXAMPLES/SIR/data/`, which is also shared with the Bayesian script.

```matlab
cd EXAMPLES/SIR
run_SIR_CUQDyn1Plus           % reads CSV data + runs FIM variant
run_SIR_CUQDyn1Plus_HybridCov % reads same data, runs Hybrid variant
SBC_SIR_FIM_vs_HybridCov      % eSS LOO refits
SBC_SIR_FIM_vs_HybridCov_fast % guarded local LOO refits
```

### Alpha-pinene isomerization (5 states, 5 parameters)

States `x1`-`x4` observed at 9 time points; `x5` unobserved after the initial condition. Uses experimental (not synthetic) measurement data.

```matlab
cd EXAMPLES/AP
run_AP_CUQDyn1Plus_partobs_example
run_AP_CUQDyn1Plus_HybridCov_partobs_example
SBC_AP_FIM_vs_HybridCov      % eSS LOO refits
SBC_AP_FIM_vs_HybridCov_fast % guarded local LOO refits
```

Each run creates a timestamped results directory containing:

| File | Contents |
|---|---|
| `hybrid_uq_plot.png` / `.fig` / `.pdf` / `.eps` | Prediction bands for all states |
| `results_detailed.xlsx` | Multi-sheet Excel: config, data, UQ bands, covariance, LOO ensemble |
| `trajectory_nrmse_tables.xlsx` | Compact post-fit trajectory error, coverage, and interval-width tables |
| `uq_diagnostics.xlsx` | Optional UQ quality diagnostics when `diagnose_uq_quality` is called |
| `CUQDyn1_Plus_results.mat` | Full `results` struct |
| `diag_*.png` / `.fig` / `.pdf` / `.eps` | HybridCov only: marginal std dev comparison, LOO correlation matrix, FIM vs Hybrid band comparison |

---

## Simulation-based calibration (SBC)

Each example includes an SBC script that evaluates frequentist coverage over many synthetic datasets:

```matlab
cd EXAMPLES/LV
SBC_LV2_FIM_vs_HybridCov             % separate FIM and HybridCov fits
SBC_LV2_FIM_vs_HybridCov_sharedfit   % stricter shared-fit comparison
```

The original SBC scripts generate **n** synthetic datasets, run CUQDyn1_Plus and CUQDyn1_Plus_HybridCov separately on each, and report:

- Pointwise coverage by time  
- Distribution of per-replicate coverage  
- Mean prediction band width  
- Full-data parameter recovery statistics

The shared-fit LV script fits each synthetic dataset once with HybridCov, then derives both FIM and HybridCov bands from the same fitted trajectory, LOO ensemble, residual variance, and sensitivity linearization. This removes stochastic optimiser differences from the FIM-vs-Hybrid comparison and is preferred when the goal is to isolate the covariance construction itself.

---

## Adding a custom model

The recommended route is to define a model once in a high-level problem
struct, then generate the legacy `prob_mod_dynamics_<Name>.m` and
`prob_mod_cost_<Name>.m` files used by the existing CUQDyn pipeline. The same
definition can also generate a readable synthetic-data script.

Start from the copyable cheatsheet:

```matlab
edit EXAMPLES/problem_definition_template.m
```

Save a copy as `define_problem_<Name>.m`, then fill in states, parameters,
ODE right-hand sides, bounds, data metadata, and residual-normalization
settings.

Minimal example:

```matlab
problem.name = "MyModel";
problem.states = ["x1"; "x2"];
problem.parameters = ["a"; "b"; "c"];
problem.odes = [
    "a*x1 - b*x1*x2"
    "b*x1*x2 - c*x2"
];

problem.initial_guess = [0.5; 0.02; 0.4];
problem.parameter_bounds.lower = [0.01; 0.001; 0.01];
problem.parameter_bounds.upper = [5; 1; 5];
problem.observed_states = "x2";

problem.synthetic_data.times = linspace(0, 20, 41)';
problem.synthetic_data.initial_values = [10; 5];
problem.synthetic_data.true_parameters = [0.5; 0.02; 0.4];
problem.synthetic_data.observed_state_indices = 2;
problem.synthetic_data.noise_model = "additive_gaussian_mean_percent";
problem.synthetic_data.noise_percent = 10;
problem.synthetic_data.rng_seed = 101;
problem.synthetic_data.min_observed_value = 0;
problem.synthetic_data.output_folder = "data";
problem.synthetic_data.output_file = "my_model_data.csv";

problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "explicit";
problem.cost.sigma = 0.1;          % one value per observed state
problem.cost.sigma_is_known = true;
```

Generate the modules:

```matlab
problem = define_problem_MyModel();
cuqdyn_validate_problem(problem);
cuqdyn_generate_problem_files(problem, pwd);
```

Generate a data-generation script:

```matlab
generatedDir = fullfile(pwd, 'generated_problem');
cuqdyn_generate_data_script(problem, generatedDir, ...
    'Overwrite', true);
```

Or generate the CSV directly:

```matlab
generatedDir = fullfile(pwd, 'generated_problem');
cuqdyn_generate_problem_files(problem, generatedDir, 'Overwrite', true);
addpath(generatedDir, '-begin');
out = cuqdyn_generate_synthetic_data(problem, 'BaseDir', pwd);
```

This writes:

```text
prob_mod_dynamics_MyModel.m
prob_mod_cost_MyModel.m
```

The generated dynamics function uses `zeros(..., 'like', y)` so complex-step
sensitivity calculations work for newly generated problems. The generated cost
file is a thin wrapper around `prob_mod_cost_Generic`, so residual weighting is
controlled through `cost_opts` rather than hard-coded into each problem file.
The generated data script calls `cuqdyn_generate_synthetic_data`, which writes
CSV files in the same convention used by `loadStateData`: all states at `t=0`,
finite observed states after `t=0`, and `NaN` hidden states after `t=0`.

Generated `generated_problem/` folders are disposable local outputs and are
ignored by Git. Keep `define_problem_<Name>.m` as the source of truth. A small
LV snapshot is committed under `EXAMPLES/generated_reference/LV/` only as an
illustrative example of generator output.

### Residual Normalization

When observed states have very different units or magnitudes, use weighted
residuals. The supported declarations are:

```matlab
% Raw residuals: residual
problem.cost.residual_model = "none";

% Known measurement standard deviations: residual ./ sigma
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "explicit";
problem.cost.sigma = [0.1, 25.0];   % one sigma per observed state

% Synthetic benchmark convention:
% sigma_j = noise_percent/100 * mean(Y_reference(:, observed_idx(j)))
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "from_reference_trajectory_mean";
problem.cost.noise_percent = 10;

% Manual deterministic scaling: residual .* observed_state_weights
problem.cost.residual_model = "state_weights";
problem.cost.observed_state_weights = [1/0.1, 1/25.0];
```

Build runtime cost options with:

```matlab
cost_opts = cuqdyn_cost_options_from_problem(problem);

% Or, when sigma_mode is "from_reference_trajectory_mean":
cost_opts = cuqdyn_cost_options_from_problem(problem, Y_true, observed_idx);
```

Then attach them to the MEIGO options used by the existing examples:

```matlab
opts = cuqdyn_default_options(numel(problem.parameters));
opts.cost = cost_opts;
meigo_opts = opts.meigo;
meigo_opts.cost_opts = opts.cost;
```

For generated synthetic data, `known_sigma` is statistically preferred because
optimization, FIM covariance, and residual diagnostics all use the same
observation-error scale.

### Run Script

Copy any `run_*_example.m` and update the generated model handles,
state/parameter counts, bounds, data path, and cost options:

```matlab
clear mex; clear all; close all; clc;
addpath(genpath('../../'));

problem = define_problem_MyModel();
dynamics_handle = @prob_mod_dynamics_MyModel;
cost_handle     = @prob_mod_cost_MyModel;
nstates         = numel(problem.states);
n_params        = numel(problem.parameters);
guess_params    = problem.initial_guess(:)';
lb_params       = problem.parameter_bounds.lower(:)';
ub_params       = problem.parameter_bounds.upper(:)';
alp             = 0.025;    % 95% two-sided CI

opts = cuqdyn_default_options(n_params);
opts.cost = cuqdyn_cost_options_from_problem(problem);
meigo_opts = opts.meigo;
meigo_opts.cost_opts = opts.cost;

[times, all_state_data, ic, observed_data, observed_idx] = ...
    loadStateData('data', 'mydata.csv', nstates);

nowTime   = datetime('now');
resultDir = "Results_" + string(nowTime, 'yyyy-MM-dd_HH-mm-ss');
mkdir(resultDir);

results = CUQDyn1_Plus(cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, ic, observed_data, observed_idx, resultDir, meigo_opts);

plot_hybrid_uq(results, resultDir);
save_results_to_excel_detailed(results, resultDir, true_params, ...
    guess_params, lb_params, ub_params, 'mydata.csv');
print_param_recovery(results, true_params, {'a','b','c'}, alp);
save_trajectory_nrmse_tables(results, resultDir);
diagnose_uq_quality(results, resultDir, {'a','b','c'}, {'x1','x2'}, ...
                    lb_params, ub_params);
```

To use the HybridCov variant, replace `CUQDyn1_Plus` with `CUQDyn1_Plus_HybridCov` — the interface is identical.

The maintained examples now include `define_problem_<Example>.m` files and
generated-module equivalence checks. From the repository root:

```matlab
reports = check_generated_problem_definitions();
```

This regenerates modules in temporary folders and checks that generated
dynamics/cost outputs match the current legacy files without committing
per-example generated outputs.

---

## Output structure (`results` struct)

Both functions return the same core fields; HybridCov adds diagnostic covariance fields.

| Field | Size | Description |
|---|---|---|
| `parameters_init` | 1 × n_params | Best-fit parameters (full data) |
| `media_tot` | m × n_states | Best-fit ODE trajectory |
| `media_matrix` | m × n_states × (m−1) | LOO trajectory ensemble |
| `UQ_lower` | m × n_states | Lower prediction band (all states) |
| `UQ_upper` | m × n_states | Upper prediction band (all states) |
| `Cov_p` | n_params × n_params | Parameter covariance (FIM or Hybrid) |
| `Cov_log` | n_params × n_params | Log-parameter covariance when log FIM is used; diagnostic otherwise |
| `std_y` | m × n_states | Delta-method state standard deviations |
| `loo_params` | (m−1) × n_params | LOO parameter vectors |
| `resid_loo` | (m−1) × n_obs | LOO absolute residuals |
| `observed_idx` | 1 × n_obs | Column indices of observed states |
| `alp` | scalar | Significance level used |
| `options` | struct | Effective MEIGO/refit/ODE/cost/UQ/FIM options saved with the run |
| `diagnostics.fim` | struct | FIM parameterization, covariance method, singular values, rank, condition number, ridge, weak directions, and residual variance scale |
| `diagnostics.fim_reliability` | struct | Weak-direction sensitivity fractions and per-state unreliable-band flags |

**HybridCov additional fields:**

| Field | Description |
|---|---|
| `Cov_p_fim` | FIM-only covariance (diagnostic) |
| `Cov_p_loo` | LOO-only empirical covariance (diagnostic) |
| `R_loo` | LOO correlation matrix |
| `D_fim` | FIM marginal standard deviations |

---

## Utility functions

### `plot_hybrid_uq(results, resultDir)`

Generates a multi-panel figure with one subplot per state. Each panel shows:
- Shaded conformal/delta-method PI (colour-matched per state)
- Solid best-fit line (solid = observed, dashed = unobserved)
- Data markers for observed states

Saves as `hybrid_uq_plot.png`, `.fig`, `.pdf`, and `.eps`.

### `print_param_recovery(results, true_params, param_names, alp)`

Prints a console table with columns: True value, Estimate, CI lower, CI upper, Relative error %, In CI flag. Automatically detects HybridCov results and adds a FIM/LOO/Hybrid marginal standard deviation comparison. The `alp` argument is optional (defaults to 0.05).

### `savefig_png(fig, base_path, res)`

Saves a figure as `.png`, `.fig`, `.pdf`, and `.eps`. Uses `exportgraphics` (R2020a+) before `savefig` to avoid the `SubplotListenersManager` crash that occurs with `saveas` when `sgtitle` and `linkaxes` are used together. Accepts both `char` and MATLAB `string` paths. Default resolution is 150 DPI.

### `save_results_to_excel_detailed(results, resultDir, ...)`

Exports the full results struct to a multi-sheet annotated Excel workbook covering: configuration, times, observed data, UQ bands, best-fit trajectory, parameter covariance, LOO ensemble, and diagnostics.

### `save_trajectory_nrmse_tables(results, resultDir, state_names, fileBase)`

Writes compact post-fit tables comparing `results.media_tot` against finite entries in `results.all_state_data`. The workbook includes:
- `DataSummary`: observed/unobserved state labels and number of finite data points
- `ErrorSummary`: RMSE, MAE, data range, and NRMSE %
- `UQSummary`: empirical coverage of finite data by `UQ_lower`/`UQ_upper` and normalized interval width
- `PointwiseResiduals`: time-by-time residuals for finite data

`state_names` and `fileBase` are optional. If state names are omitted, generic `State1`, `State2`, ... labels are used.

### `diagnose_uq_quality(results, resultDir, param_names, state_names, lb_params, ub_params)`

Runs independent post-fit diagnostics without changing the core CUQDyn1 algorithms. It writes `uq_diagnostics.xlsx` and `uq_diagnostics.mat` with:
- covariance condition number and eigenvalues
- residual variance estimates with and without the initial condition row
- parameter standard deviations and relative standard deviations
- parameter correlation matrix
- stored FIM rank, condition number, weak-direction count, and weak-direction reliability flags when available
- optional near-bound flags when parameter bounds are supplied
- HybridCov-specific FIM/LOO/Hybrid marginal standard deviation comparison when those fields exist

### `bootstrap_trajectory_uq(results, dynamics_handle, cost_handle, lb_params, ub_params, resultDir, boot_opts)`

Runs an optional parametric bootstrap for trajectory uncertainty. Starting from an existing `results` struct, it estimates observed-state noise from post-initial residuals, simulates bootstrap observed datasets around the fitted trajectory, refits each dataset, propagates each refit through the ODE, and forms empirical quantile bands.

Minimal usage:

```matlab
boot_opts = struct('n_boot', 100, 'alp', 0.025);
boot = bootstrap_trajectory_uq(results, dynamics_handle, cost_handle, ...
    lb_params, ub_params, resultDir, boot_opts);
```

This method is slower than the FIM/HybridCov delta-method bands because it performs repeated optimiser refits, but it relies less on local Gaussian linearization.

---

## Bayesian ABC-SMC comparison (Python)

The `pymc_matlab/` directory contains PyMC implementations of ABC-Sequential Monte Carlo for the LV, SIR, AP, and NF-kB examples. These provide a Bayesian posterior reference independent of the optimisation-based CUQDyn1_Plus approach.

**Setup** (requires Python with uv or pip):

```bash
cd pymc_matlab
uv run python lv_pymc.py      # Lotka-Volterra
uv run python sir_pymc.py     # SIR
uv run python ap_pymc.py      # Alpha-pinene
uv run python nfkb_pymc.py    # NF-kB
```

Each maintained script reads the identical dataset used by the corresponding MATLAB scripts, runs ABC-SMC sampling, and saves:
- Posterior predictive plots (dual 95%/50% quantile bands)
- `posterior_samples.csv` — all posterior draws
- `mean_trajectory.csv` — posterior mean ODE solution
- Per-state trajectory ensembles (500 samples, for uncertainty bands)
- Per-observed-state posterior predictive trajectory ensembles with RMSE-based observation-noise augmentation
- Per-state `*_latent_trajectories.csv` exports preserving parameter-uncertainty-only trajectories
- SMC diagnostics (R-hat, ESS, noise-augmented predictive coverage)

The PyMC scripts are tuned for comparison with the current CUQDyn examples: SIR, AP, and NF-kB use 1000 ABC-SMC draws per chain, LV uses 4000 draws per chain, AP priors match the widened CUQDyn AP bounds, and LV/SIR use tighter ODE tolerances inside the ABC simulator.

After running the PyMC workflows and the corresponding CUQDyn examples, `pymc_matlab/compare_cuqdyn_pymc.m` creates unified CUQDyn-versus-PyMC parameter tables, trajectory-band tables, and side-by-side predictive figures. The report generator `scripts/generate_cuqdyn_pymc_comparison_report.py` turns the latest comparison folder into a LaTeX report under `REPORTS/`.

The posterior mean parameter estimates will differ slightly from the CUQDyn1_Plus maximum-likelihood estimates — this is expected: both methods converge to the true values asymptotically, but on finite noisy data the posterior mean (with prior regularisation) and the MLE (no regularisation) produce different point estimates.

---

## Coverage interpretation

The `alp` parameter controls the nominal two-sided coverage level:

| `alp` | Nominal coverage |
|---|---|
| 0.10 | 80% |
| 0.05 | 90% (default in most scripts) |
| 0.025 | 95% |

For observed states, coverage is conformal-style and distribution-free with respect to residual shape, subject to exchangeability/calibration assumptions. For unobserved states, coverage is approximate and depends on model correctness, local identifiability, residual assumptions, and the quality of the linear approximation near the optimum. The included SBC scripts and `diagnose_uq_quality` should be used to check whether FIM, HybridCov, or bootstrap bands are adequate for a particular model and dataset.

---

## Citation

If you use CUQDyn1_Plus in your work, please cite:

> Portela, A. and Banga J.R. (2026). CUQDyn1_Plus: Hybrid Conformal–Gaussian Uncertainty Quantification for Partially Observed Dynamical Systems. *[journal/preprint in preparation]*

## Acknowledgements

This toolbox uses optimisers from MEIGO:
- Egea JA, Henriques D, Cokelaer T, Villaverde AF, MacNamara A, Danciu DP, Banga JR and Saez-Rodriguez J (2014) MEIGO: an open-source software suite based on metaheuristics for global optimization in systems biology and bioinformatics. BMC Bioinformatics 15:136.

The conformal prediction framework used here is an extension of the one initially developed for fully observed systems in:
- Portela, A., J.R. Banga, M. Matabuena (2025) Conformal Prediction for Uncertainty Quantification in Dynamic Biological Systems. PLOS Computational Biology 21(5): e1013098.

## Contact

Alberto Portela, email: albertoportela99@gmail.com  
Julio R. Banga, email: j.r.banga@csic.es

Computational Biology Lab  
MBG-CSIC (Spanish National Research Council)  
Pontevedra, Spain  
[www.bangalab.org](https://www.bangalab.org)

## License

GPLv3 License — see `LICENSE` file.
