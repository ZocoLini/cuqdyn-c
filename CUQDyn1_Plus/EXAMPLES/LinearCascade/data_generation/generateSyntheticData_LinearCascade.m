%% generateSyntheticData_LinearCascade.m
% Generate analytic synthetic CSVs for the two- and three-state linear
% cascade examples in EXAMPLES/LinearCascade/data.
%
% The generated CSVs follow the CUQDyn example-data convention:
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
generate_two_state = true;
generate_three_state = true;
noise_level_percent = 7.5;
rng_seed = 321;
min_observed_value = 0;
make_plots = true;

dataDir = fullfile(exampleDir, 'data');
if ~exist(dataDir, 'dir'), mkdir(dataDir); end

if generate_two_state
    generate_case(dataDir, 'linear_cascade_known_truth_partobs.csv', ...
        (0:0.5:20)', [10, 0], [0.35, 0.12], 2, 5, ...
        min_observed_value, make_plots, 123);
end

if generate_three_state
    generate_case(dataDir, 'linear_cascade3_known_truth_partobs.csv', ...
        (0:1.0:35)', [10, 0, 0], [0.45, 0.16, 0.055], 3, ...
        noise_level_percent, min_observed_value, make_plots, rng_seed);
end

function generate_case(dataDir, output_filename, time_points, initial_conditions, ...
        true_parameters, observed_idx, noise_pct, min_observed_value, make_plots, rng_seed)
    rng(rng_seed);
    nstates = numel(initial_conditions);
    is_observed = false(1, nstates);
    is_observed(observed_idx) = true;

    Y_true = linear_cascade_solution(time_points, initial_conditions, true_parameters);
    Y_data = apply_synthetic_noise(Y_true, is_observed, noise_pct, ...
        min_observed_value);
    assert_no_negative_finite_data(Y_data, output_filename);

    headers = [{'time'}, arrayfun(@(j) sprintf('x%d', j), 1:nstates, ...
        'UniformOutput', false)];
    writetable(array2table([time_points, Y_data], 'VariableNames', headers), ...
        fullfile(dataDir, output_filename));

    fprintf('Generated %s\n', fullfile(dataDir, output_filename));
    fprintf('Observed state indices: %s\n', mat2str(observed_idx));
    fprintf('Noise model: sigma_j = %.3g * mean(Y_true(:,j)); t=0 exact.\n', ...
        noise_pct / 100);

    if make_plots
        plot_synthetic_data(time_points, Y_true, Y_data, is_observed, output_filename);
    end
end

function Y = linear_cascade_solution(t, y0, p)
    t = t(:);
    A = cascade_matrix(p);
    Y = zeros(numel(t), numel(y0));
    for i = 1:numel(t)
        Y(i, :) = (expm(A .* t(i)) * y0(:)).';
    end
end

function A = cascade_matrix(p)
    if numel(p) == 2
        k1 = p(1);
        k2 = p(2);
        A = [-k1,  0; ...
              k1, -k2];
    elseif numel(p) == 3
        k1 = p(1);
        k2 = p(2);
        k3 = p(3);
        A = [-k1,  0,   0; ...
              k1, -k2,  0; ...
              0,   k2, -k3];
    else
        error('LinearCascade:InvalidParameterCount', ...
            'Expected two or three cascade parameters.');
    end
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
    figure('Color', 'w', 'Name', label);
    tiledlayout(numel(is_observed), 1, 'TileSpacing', 'compact');
    for j = 1:numel(is_observed)
        nexttile; hold on; grid on;
        plot(T, Y_true(:, j), 'k-', 'LineWidth', 1.5);
        plot(T, Y_data(:, j), 'ro', 'MarkerFaceColor', 'r');
        title(sprintf('%s state x%d', label, j), 'Interpreter', 'none');
        xlabel('Time');
        ylabel(sprintf('x%d', j));
        if is_observed(j)
            legend('Noise-free', 'Synthetic data', 'Location', 'best');
        else
            legend('Noise-free', 'Initial condition only', 'Location', 'best');
        end
    end
end
