function n_bad = check_problem(settings_file)
%CHECK_PROBLEM Do the C and the MATLAB side define the same problem?
%
%   n_bad = check_problem(settings_file)
%
% Loads the problem like every layer does (load_problem) and prints one line
% per quantity both sides define - sizes, time grid, initial condition,
% observed states, bounds, initial point, residual model, sigma. Returns the
% number of disagreements; run_validation.sh references stops on any.

pb = load_problem(settings_file, 'Strict', false);

fprintf('Problem "%s": MATLAB definition define_problem_%s (%s)\n', ...
    pb.name, pb.matlab_name, pb.exdir);
fprintf('  %d states, %d parameters, %d time points, observed: %s\n', ...
    pb.nstates, pb.n_params, pb.m, mat2str(pb.observed_idx(:).'));
fprintf('  run settings from the C side: alp %g, rtol %g, atol %s, budget %d\n', ...
    pb.alp, pb.settings.rtol, mat2str(unique(pb.settings.atol)), pb.maxeval);
if ~pb.has_meigo
    fprintf('  MEIGO64 not found in %s (layers 3-6 need it)\n', pb.meigo_dir);
end

n_bad = 0;
for i = 1:numel(pb.checks)
    c = pb.checks(i);
    if c.ok
        fprintf('  ok        %s\n', c.field);
    elseif c.warning
        fprintf('  warning   %s\n            C side:      %s\n            MATLAB side: %s\n', ...
            c.report{:});
    else
        n_bad = n_bad + 1;
        fprintf('  MISMATCH  %s\n            C side:      %s\n            MATLAB side: %s\n', ...
            c.report{:});
    end
end
if n_bad == 0
    fprintf('  both sides define the same problem\n');
end
end
