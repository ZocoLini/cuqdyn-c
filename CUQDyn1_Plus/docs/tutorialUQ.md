# CUQDyn1_Plus LV Tutorial: Three Prediction-UQ Workflows

This tutorial summarizes the Lotka-Volterra example in
`EXAMPLES/LV/tutorial_LV_three_prediction_UQ_methods.m`. It is the cheapest
example for comparing the three prediction uncertainty workflows currently
available in CUQDyn1_Plus:

1. FIM delta-method trajectory bands with `CUQDyn1_Plus`
2. HybridCov delta-method trajectory bands with `CUQDyn1_Plus_HybridCov`
3. Parametric bootstrap latent trajectory bands with `bootstrap_trajectory_uq`

The LV tutorial uses a partially observed predator-prey dataset where prey is
observed and predator is unobserved after the initial condition.

The hand-written LV dynamics and cost files remain in place, but the same
problem is also declared in `EXAMPLES/LV/define_problem_LV.m`. That high-level
definition can regenerate legacy-compatible `prob_mod_dynamics_LV.m` and
`prob_mod_cost_LV.m` files automatically. It also declares the synthetic-data
settings needed to generate a CUQDyn-formatted CSV.

## Setup

From the repository root, start MATLAB and run:

```matlab
setPath_CUQDyn1_Plus
cd EXAMPLES/LV
tutorial_LV_three_prediction_UQ_methods
```

MEIGO must be available either through the `MEIGO64_PATH` environment variable
or by placing `MEIGO64-master/` in the repository root. The local
`MEIGO64-master/` folder is intentionally ignored by Git.

To inspect or regenerate the LV problem modules without changing the tutorial
workflow, run:

```matlab
problem = define_problem_LV();
cuqdyn_validate_problem(problem);
cuqdyn_generate_problem_files(problem, fullfile(pwd, 'generated_problem'), ...
    'Overwrite', true);
check_generated_LV_problem
```

The check writes generated files to a temporary folder and compares their
dynamics/cost outputs with the legacy files. Per-example `generated_problem/`
folders are disposable local outputs and are ignored by Git. A small committed
LV snapshot is available under `EXAMPLES/generated_reference/LV/` for
inspection. For a schema overview and residual-normalization options, see
`EXAMPLES/problem_definition_template.m`.

To generate a readable LV data-generation script from the same definition:

```matlab
problem = define_problem_LV();
cuqdyn_generate_data_script(problem, fullfile(pwd, 'generated_problem'), ...
    'Overwrite', true);
```

The generated script calls `cuqdyn_generate_synthetic_data`, writes the CSV
using the same `loadStateData` convention as the bundled examples, and validates
that finite generated data are nonnegative.

## Tutorial Settings

The tutorial script exposes two main knobs:

```matlab
opts.meigo.maxeval = 1500;
boot_opts.n_boot = 50;
```

For a quick smoke test, these can be reduced, for example:

```matlab
opts.meigo.maxeval = 500;
boot_opts.n_boot = 10;
```

Low bootstrap counts are useful only to verify that the workflow executes.
Coverage and interval width should not be interpreted strongly from very small
bootstrap runs.

Because the LV dataset is synthetic, the tutorial uses the same additive
Gaussian observation-error model used by the data generator:

```matlab
opts.cost.residual_model = 'known_sigma';
opts.cost.sigma = cuqdyn_synthetic_sigma_from_trajectory(...);
```

This means optimisation and FIM covariance are based on standardized residuals,
while the metric tables still report raw RMSE/MAE/NRMSE in the original state
units.

The same residual-normalization declaration is present in `define_problem_LV.m`
as:

```matlab
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "from_reference_trajectory_mean";
problem.cost.noise_percent = 10;
```

## Method 1: FIM Delta-Method UQ

The FIM workflow is run with:

```matlab
fim_results = CUQDyn1_Plus(cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, ic, observed_data, observed_idx, fimDir, meigo_opts);
```

For observed states, CUQDyn1_Plus uses leave-one-out conformal prediction
bands. For unobserved states, it uses local Gaussian delta-method bands based
on the Fisher information matrix covariance estimate.

The tutorial then calls:

```matlab
state_names = {'Prey', 'Predator'};
save_trajectory_nrmse_tables(fim_results, fimDir, state_names);
diagnose_uq_quality(fim_results, fimDir, param_names, state_names, lb_params, ub_params);
```

These functions produce compact Excel tables for trajectory fit quality,
coverage, interval widths, residuals, covariance conditioning, parameter
standard deviations, correlations, and near-bound diagnostics.

## Method 2: HybridCov Delta-Method UQ

The HybridCov workflow is run with:

```matlab
hyb_results = CUQDyn1_Plus_HybridCov(cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, ic, observed_data, observed_idx, hybDir, meigo_opts);
```

HybridCov uses the same observed-state conformal bands as the FIM workflow. For
unobserved states, it keeps the FIM marginal parameter uncertainty scale but
uses the leave-one-out parameter ensemble to estimate the parameter correlation
structure.

HybridCov is an empirical covariance variant, not a distribution-free
guarantee. In the shared-fit LV simulation-based calibration script, FIM and
HybridCov gave similar predator coverage, so HybridCov should be checked per
model rather than assumed to improve every example.

## Method 3: Bootstrap Trajectory UQ

The bootstrap workflow is a post-fit analysis. In the tutorial it starts from
the FIM result:

```matlab
boot = bootstrap_trajectory_uq(fim_results, dynamics_handle, cost_handle, ...
    lb_params, ub_params, bootDir, boot_opts);
```

The function estimates observation noise from the fitted observed-state
residuals, simulates bootstrap observed datasets around the fitted trajectory,
refits the parameters, propagates each fitted trajectory, and computes empirical
quantile bands.

The bootstrap bands are latent ODE trajectory bands. They are not noisy
observation prediction intervals. Therefore, coverage against noisy prey
measurements is not the main target for the bootstrap output. The tutorial
separates observed-data metrics from latent true-trajectory coverage for this
reason.

## Output Files

Each tutorial run creates a timestamped folder such as:

```text
EXAMPLES/LV/Tutorial_LV_three_UQ_methods_YYYY-MM-DD_HH-MM-SS/
```

The main subfolders are:

```text
FIM/
HybridCov/
Bootstrap_from_FIM/
```

Each method folder contains trajectory summary tables. FIM and HybridCov also
contain UQ diagnostic workbooks and `run_options.xlsx`, which records the
effective optimizer, ODE, and UQ settings. The bootstrap folder contains
`bootstrap_run_options.xlsx`. The tutorial root contains the cross-method
comparison workbook:

```text
three_uq_methods_metric_comparison.xlsx
```

## Interpreting a Representative LV Run

With `meigo_opts.maxeval = 1500` and `boot_opts.n_boot = 50`, the user observed:

| Method | State | Latent coverage (%) | Mean interval width | Normalized mean interval width |
|---|---:|---:|---:|---:|
| FIM | Prey | 100 | 14.967 | 0.19445 |
| FIM | Predator | 100 | 13.557 | 0.18131 |
| HybridCov | Prey | 100 | 14.970 | 0.19448 |
| HybridCov | Predator | 100 | 13.613 | 0.18207 |
| Bootstrap | Prey | 100 | 2.5075 | 0.032577 |
| Bootstrap | Predator | 100 | 10.715 | 0.14331 |

For this single LV dataset, the bootstrap latent trajectory bands were sharper
than the delta-method bands while still covering the known latent trajectory.
This is encouraging, but it is not a calibration guarantee. Repeated simulation
studies are needed to assess whether the bootstrap bands maintain nominal
coverage across datasets.

The same run also showed low bootstrap coverage against noisy prey observations.
That is expected because the bootstrap output is a latent trajectory band. If
the goal is coverage of future noisy observations, an observation-noise
predictive interval should be added on top of the latent trajectory uncertainty.

## Generalizing to Other Examples

For new models, prefer starting from a high-level problem definition rather than
writing `prob_mod_dynamics_*` and `prob_mod_cost_*` by hand. Copy
`EXAMPLES/problem_definition_template.m`, fill in the states, parameters, ODE
right-hand sides, observed states, bounds, and `problem.cost` residual scaling,
plus `problem.synthetic_data` settings, then generate the legacy modules and a
data-generation script:

```matlab
problem = define_problem_MyModel();
cuqdyn_validate_problem(problem);
cuqdyn_generate_problem_files(problem, myExampleDir, 'Overwrite', true);
cuqdyn_generate_data_script(problem, fullfile(myExampleDir, 'generated_problem'), ...
    'Overwrite', true);
```

The maintained examples can be checked together from the repository root:

```matlab
reports = check_generated_problem_definitions();
```

For a compact hidden-state stress test after the LV tutorial, use
LinearCascade3. It is a three-state linear cascade where only the downstream
state `x3` is observed, so the upstream states `x1` and `x2` are inferred
indirectly:

```matlab
cd EXAMPLES/LinearCascade
diagnose_LinearCascade3_known_truth
```

The script compares CUQDyn1_Plus against an independent matrix-exponential
reference and writes `linear_cascade3_numerics_summary.xlsx`. The related
`SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit` scripts are useful for comparing
FIM and HybridCov hidden-state coverage under repeated synthetic datasets.

The trajectory table function can be called after any CUQDyn1_Plus,
CUQDyn1_Plus_HybridCov, or bootstrap result:

```matlab
state_names = {'State1', 'State2', 'State3'};  % replace with model names
metrics = save_trajectory_nrmse_tables(results, resultDir, state_names);
```

Use one name per state, in the same order as the ODE state vector and CSV data
columns. For example:

```matlab
% LV
state_names = {'Prey', 'Predator'};

% SIR
state_names = {'Susceptible', 'Infected', 'Recovered'};

% AP
state_names = {'AlphaPinene', 'Dipentene', 'AlloOcimene', ...
    'Pyronene', 'Dimer'};
```

For FIM and HybridCov results, diagnostics can also be added:

```matlab
diagnose_uq_quality(results, resultDir, param_names, state_names, lb_params, ub_params);
```

For bootstrap trajectory UQ, first run one of the main CUQDyn1_Plus methods,
then call `bootstrap_trajectory_uq` using the fitted result as input.

## Practical Recommendations

- Use FIM bands as the fastest baseline for prediction UQ.
- Use HybridCov as an empirical covariance alternative and check it with
  diagnostics or calibration studies.
- Use bootstrap trajectory UQ when local Gaussian approximations look fragile,
  especially when covariance diagnostics show high condition numbers or strong
  parameter correlations.
- Interpret bootstrap bands as latent trajectory uncertainty unless observation
  noise is explicitly added to form noisy-observation prediction intervals.
- For publication-quality bootstrap summaries, use more than the cheap tutorial
  settings and check successful replicate counts.
