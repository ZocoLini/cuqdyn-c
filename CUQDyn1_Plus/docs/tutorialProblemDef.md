# CUQDyn1_Plus Problem Definition Tutorial

This tutorial shows how to set up a new ODE problem from a high-level MATLAB
definition. The goal is to let new users define a model once, then generate the
legacy problem files and optional synthetic-data script used by CUQDyn1_Plus.

For the separate tutorial on FIM, HybridCov, and bootstrap prediction
uncertainty workflows, see `tutorialUQ.md`.

## Overview

A CUQDyn problem definition can generate:

1. `prob_mod_dynamics_<Name>.m`
2. `prob_mod_cost_<Name>.m`
3. `generateSyntheticData_<Name>.m`

The generated dynamics/cost files keep the existing CUQDyn interface unchanged.
The generated data script writes CSV files in the same convention used by
`loadStateData`:

- column 1 is time;
- columns 2:end are states;
- all states are finite at `t=0`;
- observed states are finite after `t=0`;
- hidden states are `NaN` after `t=0`.

## Start From The Template

Copy the cheatsheet:

```matlab
copyfile('EXAMPLES/problem_definition_template.m', ...
    'EXAMPLES/MyModel/define_problem_MyModel.m')
```

Then edit the copy. The required fields are:

```matlab
problem.name = "MyModel";
problem.states = ["x1"; "x2"];
problem.parameters = ["a"; "b"; "c"];
problem.odes = [
    "a*x1 - b*x1*x2"
    "b*x1*x2 - c*x2"
];
```

State and parameter names must be valid MATLAB identifiers because the
generator uses them directly in the generated dynamics function.

## Add Fitting Metadata

Declare guesses and bounds:

```matlab
problem.initial_guess = [0.5; 0.02; 0.4];
problem.parameter_bounds.lower = [0.01; 0.001; 0.01];
problem.parameter_bounds.upper = [5; 1; 5];
problem.observed_states = "x2";
problem.observed_state_indices = 2;
```

The observed-state names are useful for readability. The indices are useful for
data generation and checking.

## Declare Residual Scaling

If observed states have different units or magnitudes, declare how residuals
should be normalized. For known measurement standard deviations:

```matlab
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "explicit";
problem.cost.sigma = 0.1;          % one value per observed state
problem.cost.sigma_is_known = true;
```

For synthetic data generated with a noise percentage:

```matlab
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "from_reference_trajectory_mean";
problem.cost.noise_percent = 10;
problem.cost.sigma_is_known = true;
```

For raw unweighted residuals:

```matlab
problem.cost.residual_model = "none";
```

For manual deterministic scaling:

```matlab
problem.cost.residual_model = "state_weights";
problem.cost.observed_state_weights = [1/0.1, 1/25.0];
```

At run time, convert this declaration to CUQDyn cost options:

```matlab
cost_opts = cuqdyn_cost_options_from_problem(problem);
```

If `sigma_mode` is `"from_reference_trajectory_mean"`, provide the reference
trajectory and observed-state indices:

```matlab
cost_opts = cuqdyn_cost_options_from_problem(problem, Y_true, observed_idx);
```

## Declare Synthetic Data Settings

If you want generated benchmark data, add `problem.synthetic_data`:

```matlab
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
problem.synthetic_data.make_plots = true;
```

`min_observed_value = 0` prevents negative noisy finite observations while
preserving exact zero initial conditions. Use a small positive value only if
your measurement model requires strictly positive observations after `t=0`.

## Using Real Data

If you already have experimental or observational data, provide it as a CSV file
in the format expected by `loadStateData`.

The CSV must contain:

- column 1: time;
- columns 2:end: model states, in the same order as `problem.states`;
- row 1: initial values for **all** states;
- after row 1: finite values for observed states;
- after row 1: `NaN` for hidden or unobserved states.

For a three-state model where only state `x2` is observed after the initial
condition:

```text
time,x1,x2,x3
0,10,0,0
1,NaN,1.23,NaN
2,NaN,2.05,NaN
3,NaN,2.61,NaN
```

Then declare the data in your problem file:

```matlab
problem.data.folder = "data";
problem.data.file = "my_real_data.csv";
problem.observed_states = "x2";
problem.observed_state_indices = 2;
```

and load it in the run script:

```matlab
[times, all_state_data, ic, observed_data, observed_idx] = ...
    loadStateData(fullfile(exampleDir, problem.data.folder), ...
    problem.data.file, numel(problem.states));
```

### Real-Data Error Models

The residual/error model matters because it controls parameter fitting and FIM
covariance scaling. If observed states have different magnitudes, raw residuals
can make the largest-magnitude state dominate the fit.

If you know the measurement standard deviation for each observed state, use
`known_sigma`:

```matlab
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "explicit";
problem.cost.sigma = [0.1, 25.0];   % one sigma per observed state
problem.cost.sigma_is_known = true;
```

This is usually the best option when the instrument, assay, or preprocessing
pipeline provides uncertainty estimates.

If you do not know the measurement error model, there is no single automatic
answer. Reasonable starting points are:

```matlab
% Raw least squares: use only when observed states have comparable scales.
problem.cost.residual_model = "none";
```

or manual scale normalization:

```matlab
% Example: divide residuals by representative state scales.
problem.cost.residual_model = "state_weights";
problem.cost.observed_state_weights = [1/0.1, 1/25.0];
```

Choose state weights from defensible scales such as typical measurement
standard deviations, replicate variability, baseline-normalized units, or a
representative range/mean for each observed state. Treat these as modeling
assumptions and report them with the fit. For serious applications, compare
sensitivity to plausible weighting choices and inspect residual diagnostics.

## Validate And Generate Files

From the repository root:

```matlab
setPath_CUQDyn1_Plus
problem = define_problem_MyModel();
cuqdyn_validate_problem(problem);

exampleDir = fullfile(pwd, 'EXAMPLES', 'MyModel');
generatedDir = fullfile(exampleDir, 'generated_problem');

cuqdyn_generate_problem_files(problem, generatedDir, 'Overwrite', true);
cuqdyn_generate_data_script(problem, generatedDir, 'Overwrite', true);
```

Generated `generated_problem/` folders are disposable local outputs and are
ignored by Git. Keep `define_problem_<Name>.m` as the source of truth; regenerate
the legacy-compatible model files whenever you need to inspect or run them.

## Generate A CSV

Run the generated data script:

```matlab
cd EXAMPLES/MyModel/generated_problem
generateSyntheticData_MyModel
```

Or generate the CSV directly:

```matlab
addpath(generatedDir, '-begin');
out = cuqdyn_generate_synthetic_data(problem, ...
    'BaseDir', exampleDir, ...
    'DynamicsHandle', @prob_mod_dynamics_MyModel);
```

Then check the CSV with the standard loader:

```matlab
[times, all_state_data, ic, observed_data, observed_idx] = ...
    loadStateData(fullfile(exampleDir, 'data'), ...
    problem.synthetic_data.output_file, numel(problem.states));
```

## Use The Generated Problem In A Run

```matlab
addpath(generatedDir, '-begin');

dynamics_handle = @prob_mod_dynamics_MyModel;
cost_handle = @prob_mod_cost_MyModel;

nstates = numel(problem.states);
n_params = numel(problem.parameters);
guess_params = problem.initial_guess(:)';
lb_params = problem.parameter_bounds.lower(:)';
ub_params = problem.parameter_bounds.upper(:)';
alp = 0.025;

opts = cuqdyn_default_options(n_params);
opts.cost = cuqdyn_cost_options_from_problem(problem);
meigo_opts = opts.meigo;
meigo_opts.cost_opts = opts.cost;

resultDir = "Results_MyModel_" + string(datetime('now'), 'yyyy-MM-dd_HH-mm-ss');
mkdir(resultDir);

results = CUQDyn1_Plus(cost_handle, dynamics_handle, nstates, n_params, ...
    guess_params, lb_params, ub_params, alp, ...
    times, all_state_data, ic, observed_data, observed_idx, resultDir, ...
    meigo_opts);
```

For synthetic data with `sigma_mode = "from_reference_trajectory_mean"`, compute
`Y_true` first and call:

```matlab
opts.cost = cuqdyn_cost_options_from_problem(problem, Y_true, observed_idx);
```

## Check Built-In Examples

The maintained examples include high-level definitions. From the repository
root, run:

```matlab
reports = check_generated_problem_definitions();
```

This regenerates dynamics/cost files in temporary folders and verifies that
generated outputs match the current legacy files.

## Regression Test The Generator

The toolbox also includes an automated regression test for the high-level
problem-definition workflow:

```matlab
results = runtests('unitTests/test_problem_definition_generator.m');
table(results)
```

This test is intended for developers and advanced users who modify the problem
schema, generator, cost handling, or example definitions. It checks that:

- generated dynamics and cost modules for LV, SIR, AP, NF-kB, LinearCascade,
  and LinearCascade3 match the maintained legacy files;
- generated synthetic CSV files can be read by `loadStateData`;
- generated CSV files have the expected observed-state columns;
- finite generated data values are nonnegative.

Passing this test does not prove that a new scientific model is correct, but it
does protect the generator interface from silent regressions.

## Practical Guidance

- Keep `define_problem_<Name>.m` as the single source of truth.
- Use `known_sigma` when observation standard deviations are known.
- Use `state_weights` only for deterministic normalization when no statistical
  sigma model is available.
- Treat `generated_problem/` as disposable local output. It is ignored by Git.
- Keep committed generated snapshots only when they are deliberately documented
  as references, such as `EXAMPLES/generated_reference/LV/`.
