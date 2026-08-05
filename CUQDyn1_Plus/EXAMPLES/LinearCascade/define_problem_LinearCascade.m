function problem = define_problem_LinearCascade()
%DEFINE_PROBLEM_LINEARCASCADE High-level two-state linear cascade definition.

problem = struct();
problem.name = "LinearCascade";
problem.description = "Two-state irreversible linear cascade.";

problem.states = ["x1"; "x2"];
problem.parameters = ["k1"; "k2"];
problem.odes = [
    "-k1*x1"
    " k1*x1 - k2*x2"
];

problem.true_parameters = [0.35; 0.12];
problem.initial_values = [10; 0];
problem.initial_guess = problem.true_parameters .* [0.75; 1.35];
problem.parameter_bounds.lower = 0.2 * problem.true_parameters;
problem.parameter_bounds.upper = 3.0 * problem.true_parameters;

problem.data.folder = "data";
problem.data.file = "linear_cascade_known_truth_partobs.csv";
problem.observed_states = "x2";
problem.observed_state_indices = 2;
problem.noise_percent = 5;
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "from_reference_trajectory_mean";
problem.cost.noise_percent = problem.noise_percent;
problem.cost.sigma_is_known = true;
problem.ode.solver = "ode15s";

problem.test_state = [8; 1.5];
problem.test_initial_values = [10; 0];

problem.synthetic_data.times = (0:0.5:20)';
problem.synthetic_data.initial_values = [10; 0];
problem.synthetic_data.true_parameters = problem.true_parameters;
problem.synthetic_data.observed_state_indices = 2;
problem.synthetic_data.noise_model = "additive_gaussian_mean_percent";
problem.synthetic_data.noise_percent = problem.noise_percent;
problem.synthetic_data.rng_seed = 123;
problem.synthetic_data.min_observed_value = 0;
problem.synthetic_data.output_folder = "data";
problem.synthetic_data.output_file = problem.data.file;
problem.synthetic_data.make_plots = true;
problem.synthetic_data.ode.RelTol = 1e-7;
problem.synthetic_data.ode.AbsTol = 1e-9;
end
