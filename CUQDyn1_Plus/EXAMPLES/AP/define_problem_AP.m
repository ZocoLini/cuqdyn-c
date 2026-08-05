function problem = define_problem_AP()
%DEFINE_PROBLEM_AP High-level AP compartment model definition.

problem = struct();
problem.name = "AP";
problem.description = "Five-state AP linear compartment model.";

problem.states = ["x1"; "x2"; "x3"; "x4"; "x5"];
problem.parameters = ["k1"; "k2"; "k3"; "k4"; "k5"];
problem.odes = [
    "-(k1 + k2)*x1"
    " k1*x1"
    " k2*x1 - (k3 + k4)*x3 + k5*x5"
    " k3*x3"
    " k4*x3 - k5*x5"
];

problem.true_parameters = [5.93e-05; 2.96e-05; 2.05e-05; 2.75e-04; 4.00e-05];
problem.initial_guess = 0.8 * problem.true_parameters;
problem.parameter_bounds.lower = 0.05 * problem.true_parameters;
problem.parameter_bounds.upper = 5.0 * problem.true_parameters;

problem.data.folder = "data";
problem.data.file = "AP_measurementData_1_4.csv";
problem.observed_states = ["x1"; "x2"; "x3"; "x4"];
problem.observed_state_indices = [1, 2, 3, 4];
% AP uses unweighted residuals by default because the bundled measurement
% dataset does not declare observation standard deviations. To normalize
% differently-scaled observed states, switch to "known_sigma" or
% "state_weights" and provide one scale/weight per observed state.
problem.cost.residual_model = "none";
problem.ode.solver = "ode15s";

problem.test_state = [10; 1; 2; 0.5; 0.25];
problem.test_initial_values = problem.test_state;
problem.test_times = linspace(0, 1000, 5)';

problem.synthetic_data.times = [0; 1230; 3060; 4920; 7800; 10680; 15030; 22620; 36420];
problem.synthetic_data.initial_values = [100; 0; 0; 0; 0];
problem.synthetic_data.true_parameters = problem.true_parameters;
problem.synthetic_data.observed_state_indices = [1, 2, 3, 4];
problem.synthetic_data.noise_model = "additive_gaussian_mean_percent";
problem.synthetic_data.noise_percent = 10;
problem.synthetic_data.rng_seed = 101;
problem.synthetic_data.min_observed_value = 0;
problem.synthetic_data.output_folder = "data";
problem.synthetic_data.output_file = "AP_synthetic_data_10_partobs1_4.csv";
problem.synthetic_data.make_plots = true;
problem.synthetic_data.ode.RelTol = 1e-7;
problem.synthetic_data.ode.AbsTol = 1e-9;
end
