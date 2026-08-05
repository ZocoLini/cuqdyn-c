function problem = define_problem_NFKB()
%DEFINE_PROBLEM_NFKB High-level 15-state NF-kB problem definition.

problem = struct();
problem.name = "NFKB";
problem.description = "Fifteen-state NF-kB signaling model.";

problem.states = "x" + string((1:15)');
problem.parameters = "p" + string((1:29)');
problem.odes = [
    "p20 - p21*x1 - p17*x1"
    "p17*x1 - p19*x2 - p18*x2*x8 - p21*x2 - p2*x2*x10 + p3*x4 - p4*x2*x13 + p5*x5"
    "p19*x2 + p18*x2*x8 - p21*x3"
    "p2*x2*x10 - p3*x4"
    "p4*x2*x13 - p5*x5"
    "p11*x13 - p1*x6*x10 + p5*x5 - p23*x6"
    "p23*p22*x6 - p1*x11*x7"
    "p15*x9 - p16*x8"
    "p13 + p12*x7 - p14*x9"
    "-p2*x2*x10 - p1*x10*x6 + p9*x12 - p10*x10 - p25*x10 + p26*x11"
    "-p1*x11*x7 + p25*p22*x10 - p26*p22*x11"
    "p7 + p6*x7 - p8*x12"
    "p1*x10*x6 - p11*x13 - p4*x2*x13 + p24*x14"
    "p1*x11*x7 - p24*p22*x14"
    "p28 + p27*x7 - p29*x15"
];

problem.true_parameters = [
    0.5; 0.2; 0.1; 1; 0.1; 5e-7; 0.0001; 0.0004; 0.5; ...
    0.0001; 0.00002; 5e-7; 0.0001; 0.0004; 0.5; 0.0003; ...
    0.0025; 0.1; 0.0015; 0.000025; 0.000125; 5; ...
    0.0025; 0.01; 0.001; 0.0005; 5e-7; 0.0001; 0.0004];
problem.initial_guess = 0.8 * problem.true_parameters;
problem.parameter_bounds.lower = 0.1 * problem.true_parameters;
problem.parameter_bounds.upper = 4.0 * problem.true_parameters;

problem.data.folder = "data";
problem.data.file = "NFKB_synthetic_data_5n_36st_partobs10.csv";
problem.observed_states = problem.states([1, 2, 3, 5, 7, 9, 11, 12, 13, 15]);
problem.observed_state_indices = [1, 2, 3, 5, 7, 9, 11, 12, 13, 15];
problem.noise_percent = 5;
problem.cost.residual_model = "known_sigma";
problem.cost.sigma_mode = "from_reference_trajectory_mean";
problem.cost.noise_percent = problem.noise_percent;
problem.cost.sigma_is_known = true;
problem.ode.solver = "ode15s";

problem.test_state = linspace(0.2, 1.6, 15)';
problem.test_initial_values = problem.test_state;
problem.test_times = linspace(0, 0.05, 4)';

problem.synthetic_data.times = (0:300:3*3600)';
problem.synthetic_data.initial_values = [
    0.2; 0; 0; 0; 0; 3.155e-004; 2.2958e-003; ...
    4.78285e-003; 2.8697e-006; 2.50663e-003; 3.43573e-003; ...
    0; 0; 0; 0];
problem.synthetic_data.true_parameters = problem.true_parameters;
problem.synthetic_data.observed_state_indices = [1, 2, 3, 5, 7, 9, 11, 12, 13, 15];
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
