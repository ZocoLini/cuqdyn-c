function problem = define_problem_LinearCascade3()
%DEFINE_PROBLEM_LINEARCASCADE3 High-level three-state linear cascade definition.

problem = struct();
problem.name = "LinearCascade3";
problem.description = "Three-state irreversible linear cascade.";

problem.states = ["x1"; "x2"; "x3"];
problem.parameters = ["k1"; "k2"; "k3"];
problem.odes = [
    "-k1*x1"
    " k1*x1 - k2*x2"
    " k2*x2 - k3*x3"
];

problem.true_parameters = [0.45; 0.16; 0.055];
problem.initial_values = [10; 0; 0];
problem.initial_guess = problem.true_parameters .* [0.7; 1.25; 1.4];
problem.parameter_bounds.lower = 0.15 * problem.true_parameters;
problem.parameter_bounds.upper = 4.0 * problem.true_parameters;

problem.data.folder = "data";
problem.data.file = "linear_cascade3_known_truth_partobs.csv";
problem.observed_states = "x3";
problem.observed_state_indices = 3;
problem.noise_percent = 7.5;
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "from_reference_trajectory_mean";
problem.cost.noise_percent = problem.noise_percent;
problem.cost.sigma_is_known = true;
problem.ode.solver = "ode15s";

problem.test_state = [8; 1.5; 0.2];
problem.test_initial_values = [10; 0; 0];

problem.synthetic_data.times = (0:1.0:35)';
problem.synthetic_data.initial_values = [10; 0; 0];
problem.synthetic_data.true_parameters = problem.true_parameters;
problem.synthetic_data.observed_state_indices = 3;
problem.synthetic_data.noise_model = "additive_gaussian_mean_percent";
problem.synthetic_data.noise_percent = problem.noise_percent;
problem.synthetic_data.rng_seed = 321;
problem.synthetic_data.min_observed_value = 0;
problem.synthetic_data.output_folder = "data";
problem.synthetic_data.output_file = problem.data.file;
problem.synthetic_data.make_plots = true;
problem.synthetic_data.ode.RelTol = 1e-7;
problem.synthetic_data.ode.AbsTol = 1e-9;
end
