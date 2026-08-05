function problem = define_problem_LV()
%DEFINE_PROBLEM_LV High-level Lotka-Volterra problem definition.
%
% This definition is consumed by cuqdyn_generate_problem_files to create
% the legacy prob_mod_dynamics_LV.m and prob_mod_cost_LV.m files.

problem = struct();
problem.name = "LV";
problem.description = "Two-state Lotka-Volterra predator-prey model.";

problem.states = ["Prey"; "Predator"];
problem.parameters = ["alpha"; "beta"; "delta"; "gamma"];

% ODE right-hand sides use the state names above and parameter names.
problem.odes = [
    "(alpha - beta*Predator)*Prey"
    "(delta*Prey - gamma)*Predator"
];

problem.true_parameters = [0.5; 0.02; 0.02; 0.5];
problem.initial_guess = 0.8 * problem.true_parameters;
problem.parameter_bounds.lower = 0.2 * problem.true_parameters;
problem.parameter_bounds.upper = 2.0 * problem.true_parameters;

problem.data.folder = "data";
problem.data.file = "lv2_synthetic_data_noi10_partobs_1.csv";
problem.observed_states = "Prey";
problem.observed_state_indices = 1;
problem.noise_percent = 10;
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "from_reference_trajectory_mean";
problem.cost.noise_percent = problem.noise_percent;
problem.cost.sigma_is_known = true;
problem.ode.solver = "ode15s";

problem.synthetic_data.times = (0.0:1.0:30.0)';
problem.synthetic_data.initial_values = [10; 5];
problem.synthetic_data.true_parameters = problem.true_parameters;
problem.synthetic_data.observed_state_indices = 1;
problem.synthetic_data.noise_model = "additive_gaussian_mean_percent";
problem.synthetic_data.noise_percent = problem.noise_percent;
problem.synthetic_data.rng_seed = 101;
problem.synthetic_data.min_observed_value = 0;
problem.synthetic_data.output_folder = "data";
problem.synthetic_data.output_file = problem.data.file;
problem.synthetic_data.make_plots = true;
problem.synthetic_data.ode.RelTol = 1e-7;
problem.synthetic_data.ode.AbsTol = 1e-9;
end
