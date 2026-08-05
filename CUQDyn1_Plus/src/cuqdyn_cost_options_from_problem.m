function cost_opts = cuqdyn_cost_options_from_problem(problem, varargin)
%CUQDYN_COST_OPTIONS_FROM_PROBLEM Build cost_opts from a problem definition.
%
% cost_opts = cuqdyn_cost_options_from_problem(problem) returns filled
% residual weighting options declared in problem.cost. The returned struct is
% suitable for meigo_opts.cost_opts and is consumed by problem cost functions,
% residual variance estimation, and FIM covariance calculations.
%
% cost_opts = cuqdyn_cost_options_from_problem(problem, Y_reference,
% observed_idx) can compute known-sigma weights from a reference trajectory
% when problem.cost.sigma_mode is "from_reference_trajectory_mean".
%
% Supported residual models:
%   'none'          raw residuals.
%   'known_sigma'   residuals divided by one sigma per observed state.
%   'state_weights' residuals multiplied by one deterministic weight per
%                   observed state.

problem = cuqdyn_validate_problem(problem);

if isfield(problem, 'cost') && ~isempty(problem.cost)
    cost_opts = problem.cost;
else
    cost_opts = struct();
end

if ~isfield(cost_opts, 'residual_model') || isempty(cost_opts.residual_model)
    cost_opts.residual_model = 'none';
end

model = lower(char(cost_opts.residual_model));
switch model
    case 'none'
        cost_opts = rmfield_if_present(cost_opts, {'sigma_mode'});

    case 'known_sigma'
        if ~isfield(cost_opts, 'sigma_is_known') || isempty(cost_opts.sigma_is_known)
            cost_opts.sigma_is_known = true;
        end
        if ~isfield(cost_opts, 'sigma_mode') || isempty(cost_opts.sigma_mode)
            if isfield(cost_opts, 'sigma') && ~isempty(cost_opts.sigma)
                cost_opts.sigma_mode = 'explicit';
            else
                cost_opts.sigma_mode = 'from_reference_trajectory_mean';
            end
        end

        sigmaMode = lower(char(cost_opts.sigma_mode));
        switch sigmaMode
            case 'explicit'
                if ~isfield(cost_opts, 'sigma') || isempty(cost_opts.sigma)
                    error('cuqdyn_cost_options_from_problem:MissingSigma', ...
                        'problem.cost.sigma is required when sigma_mode="explicit".');
                end

            case 'from_reference_trajectory_mean'
                if numel(varargin) < 2
                    error('cuqdyn_cost_options_from_problem:MissingReferenceTrajectory', ...
                        ['Y_reference and observed_idx are required when ' ...
                         'sigma_mode="from_reference_trajectory_mean".']);
                end
                Y_reference = varargin{1};
                observed_idx = varargin{2};
                noisePct = getNoisePercent(problem, cost_opts);
                cost_opts.sigma = cuqdyn_synthetic_sigma_from_trajectory( ...
                    Y_reference, observed_idx, noisePct);

            otherwise
                error('cuqdyn_cost_options_from_problem:UnknownSigmaMode', ...
                    'Unknown problem.cost.sigma_mode: %s', sigmaMode);
        end

    case 'state_weights'
        if ~isfield(cost_opts, 'observed_state_weights') || isempty(cost_opts.observed_state_weights)
            error('cuqdyn_cost_options_from_problem:MissingStateWeights', ...
                ['problem.cost.observed_state_weights is required when ' ...
                 'residual_model="state_weights".']);
        end

    otherwise
        error('cuqdyn_cost_options_from_problem:UnknownResidualModel', ...
            'Unknown problem.cost.residual_model: %s', model);
end

cost_opts = cuqdyn_fill_cost_options(cost_opts);
end

function noisePct = getNoisePercent(problem, cost_opts)
if isfield(cost_opts, 'noise_percent') && ~isempty(cost_opts.noise_percent)
    noisePct = cost_opts.noise_percent;
elseif isfield(problem, 'noise_percent') && ~isempty(problem.noise_percent)
    noisePct = problem.noise_percent;
else
    error('cuqdyn_cost_options_from_problem:MissingNoisePercent', ...
        ['problem.cost.noise_percent or problem.noise_percent is required ' ...
         'when sigma_mode="from_reference_trajectory_mean".']);
end
end

function s = rmfield_if_present(s, names)
for i = 1:numel(names)
    if isfield(s, names{i})
        s = rmfield(s, names{i});
    end
end
end
