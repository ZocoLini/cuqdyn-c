%% generateSyntheticData_NFKB.m
% Generate a synthetic NF-kB CSV in EXAMPLES/NFKB/data.
%
% The generated CSV follows the CUQDyn example-data convention:
%   - column 1 is time;
%   - columns 2:end are states;
%   - row 1 contains initial conditions for every state;
%   - unobserved states are NaN after t=0.

clear; close all; clc;

scriptDir = fileparts(mfilename('fullpath'));
exampleDir = fileparts(scriptDir);
repoRoot = fullfile(exampleDir, '..', '..');
addpath(genpath(repoRoot));

%% User control panel
dynamics_handle = @prob_mod_dynamics_NFKB;

time_points = (0:300:3*3600)';
true_parameters = [0.5, 0.2, 0.1, 1, 0.1, 5e-7, 0.0001, 0.0004, ...
    0.5, 0.0001, 0.00002, 5e-7, 0.0001, 0.0004, 0.5, 0.0003, ...
    0.0025, 0.1, 0.0015, 0.000025, 0.000125, 5, 0.0025, ...
    0.01, 0.001, 0.0005, 5e-7, 0.0001, 0.0004];
initial_conditions = [0.2, 0, 0, 0, 0, 3.155e-004, 2.2958e-003, ...
    4.78285e-003, 2.8697e-006, 2.50663e-003, 3.43573e-003, ...
    2.86971e-006, 0.06, 7.888e-005, 2.86971e-006];
is_observed = [1, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1];
noise_level_percent = 5.0;
rng_seed = 101;
min_observed_value = 0;

output_filename = 'NFKB_synthetic_data_5n_36st_partobs10.csv';
make_plots = true;

%% Generate and save
rng(rng_seed);
dataDir = fullfile(exampleDir, 'data');
if ~exist(dataDir, 'dir'), mkdir(dataDir); end

ode_opts = odeset('RelTol', 1e-7, 'AbsTol', 1e-9);
[T, Y_true] = ode15s(@(t, y) dynamics_handle(t, y, true_parameters), ...
    time_points, initial_conditions, ode_opts);

Y_data = apply_synthetic_noise(Y_true, is_observed, noise_level_percent, ...
    min_observed_value);
assert_no_negative_finite_data(Y_data, output_filename);

headers = [{'time'}, arrayfun(@(j) sprintf('y%d', j), 1:size(Y_data, 2), ...
    'UniformOutput', false)];
writetable(array2table([T, Y_data], 'VariableNames', headers), ...
    fullfile(dataDir, output_filename));

fprintf('Generated %s\n', fullfile(dataDir, output_filename));
fprintf('Observed state indices: %s\n', mat2str(find(is_observed)));
fprintf('Noise model: sigma_j = %.3g * mean(Y_true(:,j)); t=0 exact.\n', ...
    noise_level_percent / 100);

if make_plots
    plot_synthetic_data(T, Y_true, Y_data, is_observed, 'NFKB');
end

function Y_data = apply_synthetic_noise(Y_true, is_observed, noise_level_percent, ...
        min_observed_value)
    Y_data = Y_true;
    observed_idx = find(is_observed);
    sigma = cuqdyn_synthetic_sigma_from_trajectory(Y_true, observed_idx, ...
        noise_level_percent);

    for k = 1:numel(observed_idx)
        j = observed_idx(k);
        Y_data(2:end, j) = Y_true(2:end, j) + ...
            sigma(k) * randn(size(Y_true, 1) - 1, 1);
        Y_data(2:end, j) = max(Y_data(2:end, j), min_observed_value);
    end

    hidden_idx = find(~is_observed);
    Y_data(2:end, hidden_idx) = NaN;
end

function assert_no_negative_finite_data(Y_data, output_filename)
    finite_values = Y_data(isfinite(Y_data));
    if any(finite_values < 0)
        error('SyntheticData:NegativeValues', ...
            'Generated negative finite values for %s.', output_filename);
    end
end

function plot_synthetic_data(T, Y_true, Y_data, is_observed, label)
    figure('Color', 'w', 'Name', [label ' synthetic data']);
    tiledlayout(numel(is_observed), 1, 'TileSpacing', 'compact');
    for j = 1:numel(is_observed)
        nexttile; hold on; grid on;
        plot(T, Y_true(:, j), 'k-', 'LineWidth', 1.5);
        plot(T, Y_data(:, j), 'ro', 'MarkerFaceColor', 'r');
        title(sprintf('%s state y%d', label, j));
        xlabel('Time');
        ylabel(sprintf('y%d', j));
        if is_observed(j)
            legend('Noise-free', 'Synthetic data', 'Location', 'best');
        else
            legend('Noise-free', 'Initial condition only', 'Location', 'best');
        end
    end
end
