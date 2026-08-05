function problem = define_problem_SIR()
%DEFINE_PROBLEM_SIR High-level SIR epidemic problem definition.

problem = struct();
problem.name = "SIR";
problem.description = "Three-state susceptible-infected-recovered model.";

problem.states = ["S"; "I"; "R"];
problem.parameters = ["beta"; "gamma"];
problem.odes = [
    "-beta*S*I"
    " beta*S*I - gamma*I"
    " gamma*I"
];

problem.initial_guess = [0.001; 0.2];
problem.parameter_bounds.lower = [0.0001; 0.01];
problem.parameter_bounds.upper = [0.01; 2.0];

problem.data.folder = "data";
problem.data.file = "sir_data.csv";
problem.observed_states = "I";
problem.observed_state_indices = 2;
problem.noise_percent = 10;
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "from_reference_trajectory_mean";
problem.cost.noise_percent = problem.noise_percent;
problem.cost.sigma_is_known = true;
problem.ode.solver = "ode15s";

problem.test_state = [0.9; 0.08; 0.02];
problem.test_initial_values = [0.99; 0.01; 0];

problem.synthetic_data.times = (0:0.5:15)';
problem.synthetic_data.initial_values = [990; 10; 0];
problem.synthetic_data.true_parameters = [0.002; 0.5];
problem.synthetic_data.observed_state_indices = 2;
problem.synthetic_data.noise_model = "additive_gaussian_mean_percent";
problem.synthetic_data.noise_percent = problem.noise_percent;
problem.synthetic_data.rng_seed = 101;
problem.synthetic_data.min_observed_value = 0;
problem.synthetic_data.output_folder = "data";
problem.synthetic_data.output_file = problem.data.file;
problem.synthetic_data.make_plots = true;
problem.synthetic_data.ode.RelTol = 1e-8;
problem.synthetic_data.ode.AbsTol = 1e-8;
end
