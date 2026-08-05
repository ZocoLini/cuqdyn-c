function problem = problem_definition_template()
%PROBLEM_DEFINITION_TEMPLATE Copyable CUQDyn problem-definition cheatsheet.
%
% Save a copy as define_problem_<Name>.m and edit the fields below. The
% generator writes legacy-compatible files:
%
%   prob_mod_dynamics_<Name>.m
%   prob_mod_cost_<Name>.m
%
% Example:
%
%   problem = define_problem_MyModel();
%   cuqdyn_validate_problem(problem);
%   cuqdyn_generate_problem_files(problem, pwd);
%
% The generated cost file delegates to prob_mod_cost_Generic, so residual
% normalization is controlled by cost_opts. Use
% cuqdyn_cost_options_from_problem to turn problem.cost into cost_opts.

problem = struct();

%% Required model identity

% Must be a valid MATLAB identifier. This becomes the generated suffix.
problem.name = "MyModel";
problem.description = "Short human-readable model description.";

%% Required states, parameters, and ODE right-hand sides

% State names and parameter names must be valid MATLAB identifiers. Use these
% exact names inside problem.odes.
problem.states = ["x1"; "x2"; "x3"];
problem.parameters = ["k1"; "k2"];

% One expression per state. These are right-hand sides only, not "dx/dt =".
problem.odes = [
    "-k1*x1"
    " k1*x1 - k2*x2"
    " k2*x2"
];

%% Optional fitting metadata

problem.true_parameters = [0.5; 0.2];       % optional, for examples/tests
problem.initial_guess = [0.4; 0.25];        % starting point for fitting
problem.parameter_bounds.lower = [0.01; 0.01];
problem.parameter_bounds.upper = [2.0; 2.0];
problem.initial_values = [10; 0; 0];

%% Optional data metadata

problem.data.folder = "data";
problem.data.file = "my_model_data.csv";
problem.observed_states = ["x2"; "x3"];
problem.observed_state_indices = [2, 3];

%% Optional synthetic-data generation metadata

% cuqdyn_generate_synthetic_data uses this block to write a CSV compatible
% with loadStateData. The convention is:
%   - all states are present at t=0;
%   - only observed states are finite after t=0;
%   - hidden states are NaN after t=0;
%   - finite generated data are validated to be nonnegative.
problem.synthetic_data.times = linspace(0, 20, 41)';
problem.synthetic_data.initial_values = problem.initial_values;
problem.synthetic_data.true_parameters = problem.true_parameters;
problem.synthetic_data.observed_state_indices = problem.observed_state_indices;
problem.synthetic_data.noise_model = "additive_gaussian_mean_percent";
problem.synthetic_data.noise_percent = 10;
problem.synthetic_data.rng_seed = 101;
problem.synthetic_data.min_observed_value = 0;
problem.synthetic_data.output_folder = "data";
problem.synthetic_data.output_file = problem.data.file;
problem.synthetic_data.make_plots = true;
problem.synthetic_data.ode.RelTol = 1e-7;
problem.synthetic_data.ode.AbsTol = 1e-9;

% Generate a readable script:
% generatedDir = fullfile(pwd, 'generated_problem');
% cuqdyn_generate_data_script(problem, generatedDir, 'Overwrite', true);
%
% Or generate the CSV directly:
% generatedDir = fullfile(pwd, 'generated_problem');
% cuqdyn_generate_problem_files(problem, generatedDir, 'Overwrite', true);
% addpath(generatedDir, '-begin');
% out = cuqdyn_generate_synthetic_data(problem, 'BaseDir', pwd);
%
% generated_problem/ folders are disposable local outputs and are ignored by
% Git. Keep define_problem_<Name>.m as the source of truth.

%% Cost / residual-normalization options

% Option A: raw residuals. Use only when observed states have comparable
% units/magnitudes or when you intentionally want unweighted least squares.
problem.cost.residual_model = "none";

% Option B: statistically preferred for known measurement noise. Provide one
% sigma per observed state. Residuals become residual ./ sigma.
% problem.cost.residual_model = "known_sigma";
% problem.cost.sigma_mode = "explicit";
% problem.cost.sigma = [0.1, 25.0];
% problem.cost.sigma_is_known = true;
% problem.cost.sigma_floor = 1e-12;

% Option C: synthetic-data helper. Sigma is computed as
% noise_percent/100 * mean(Y_reference(:, observed_idx)) for each observed
% state, matching cuqdyn_synthetic_sigma_from_trajectory.
% problem.cost.residual_model = "known_sigma";
% problem.cost.sigma_mode = "from_reference_trajectory_mean";
% problem.cost.noise_percent = 10;
% problem.cost.sigma_is_known = true;

% Option D: manual deterministic normalization. Provide one multiplicative
% weight per observed state. Residuals become residual .* weight.
% problem.cost.residual_model = "state_weights";
% problem.cost.observed_state_weights = [1/0.1, 1/25.0];

%% ODE options metadata

problem.ode.solver = "ode15s";

%% Optional generator-check inputs

% These are used only by cuqdyn_check_generated_problem_modules.
problem.test_state = [8; 1; 0.5];
problem.test_initial_values = problem.initial_values;
problem.test_times = linspace(0, 1, 5)';
end
