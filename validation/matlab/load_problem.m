function pb = load_problem(settings_file, varargin)
%LOAD_PROBLEM One validation problem, from the files and directories that define it.
%
%   pb = load_problem(settings_file)
%   pb = load_problem(settings_file, 'Solver', 'cvodes', 'LocalSolver', 'dhc')
%
% settings_file is the hand-over run_validation.sh writes for every run: what
% tools/problem_info.py extracts from the C side of the problem (cuqdyn XML,
% sacess XML, data file) plus where the MATLAB side lives:
%
%   matlab_problem       a CUQDyn1_Plus problem directory: define_problem_<X>.m
%                        with prob_mod_dynamics_<X>.m, prob_mod_cost_<X>.m and
%                        the data folder it names (EXAMPLES/<X>/ and
%                        EXAMPLES/problem_definition_template.m show the layout)
%   matlab_problem_name  <X>, only when the directory holds several definitions
%   matlab_repo          CUQDyn1_Plus root (default: this repository's copy)
%   meigo                MEIGO64 root (default: $MEIGO64_PATH, then
%                        CUQDyn/Matlab/MEIGO64-master of this repository)
%
% The C-side lines are of two kinds:
%   - run settings, taken from them so that both sides always run alike: alp,
%     rtol, atol, maxeval, and a known sigma (see the comment at its use);
%   - everything both sides define twice - sizes, time grid, initial condition,
%     observed states, bounds, initial point, residual model - which is only
%     compared. The MATLAB definition stays the reference; a mismatch is an
%     error ('Strict', false turns it into pb.checks entries, for check_problem). A
%     sigma the MATLAB convention derives differently is a warning.
%
% Options
%   'Solver'       'ode15s' (default, the reference) or 'cvodes' (layer 5:
%                  registers cvodes_solver as the ODE solver)
%   'LocalSolver'  MEIGO local solver; '' keeps the reference default
%
% Replaces the per-model blocks gen_baseline.m, gen_cost_replay.m and the
% layer-5 problem_def.m used to carry.

p = inputParser;
p.addParameter('Solver', 'ode15s', @(s) ischar(s) || isstring(s));
p.addParameter('LocalSolver', '', @(s) ischar(s) || isstring(s));
p.addParameter('Strict', true, @islogical);
p.parse(varargin{:});
o = p.Results;

here = fileparts(mfilename('fullpath'));          % validation/matlab
repo = fullfile(here, '..', '..');

st = read_settings(settings_file);
matlab_dir = st.matlab_problem;

matlab_repo = first_nonempty(field_or(st, 'matlab_repo'), fullfile(repo, 'CUQDyn1_Plus'));
if ~isfolder(fullfile(matlab_repo, 'src'))
    error('load_problem:repo', 'CUQDyn1_Plus not found in %s (no src/).', matlab_repo);
end
addpath(fullfile(matlab_repo, 'src'));

meigo = first_nonempty(field_or(st, 'meigo'), getenv('MEIGO64_PATH'), ...
    fullfile(repo, 'CUQDyn', 'Matlab', 'MEIGO64-master'));
pb.has_meigo = isfolder(meigo);
if pb.has_meigo, addpath(genpath(meigo)); end
pb.meigo_dir = meigo;

% --- the MATLAB definition ---------------------------------------------
if ~isfolder(matlab_dir)
    error('load_problem:dir', 'MATLAB problem directory not found: %s', matlab_dir);
end
addpath(matlab_dir);
X = field_or(st, 'matlab_problem_name');
if isempty(X)
    defs = dir(fullfile(matlab_dir, 'define_problem_*.m'));
    if numel(defs) ~= 1
        error('load_problem:definition', ...
            '%s holds %d define_problem_*.m files; name one (--matlab_problem_name).', ...
            matlab_dir, numel(defs));
    end
    X = regexprep(defs(1).name, '^define_problem_(.*)\.m$', '$1');
end
for f = {['define_problem_' X], ['prob_mod_dynamics_' X], ['prob_mod_cost_' X]}
    if ~isfile(fullfile(matlab_dir, [f{1} '.m']))
        error('load_problem:file', '%s.m not found in %s', f{1}, matlab_dir);
    end
end
problem = cuqdyn_validate_problem(feval(['define_problem_' X]));

pb.exdir = matlab_dir;
pb.matlab_name = X;
pb.problem = problem;
pb.dynamics = str2func(['prob_mod_dynamics_' X]);
pb.cost = str2func(['prob_mod_cost_' X]);
pb.nstates = numel(problem.states);
pb.n_params = numel(problem.parameters);
pb.guess_params = problem.initial_guess(:).';
pb.lb_params = problem.parameter_bounds.lower(:).';
pb.ub_params = problem.parameter_bounds.upper(:).';
% The true parameters sit at the top level or, for definitions that only use
% them to generate data (SIR), under synthetic_data.
pb.true_params = [];
if isfield(problem, 'true_parameters') && ~isempty(problem.true_parameters)
    pb.true_params = problem.true_parameters(:).';
elseif isfield(problem, 'synthetic_data') && isfield(problem.synthetic_data, 'true_parameters')
    pb.true_params = problem.synthetic_data.true_parameters(:).';
end
pb.has_truth = ~isempty(pb.true_params);
if ~pb.has_truth
    pb.true_params = pb.guess_params;   % layer 2 only needs one fixed theta
end
pb.dataDir = fullfile(matlab_dir, char(problem.data.folder));
pb.dataFile = char(problem.data.file);

[pb.times, pb.all_state_data, pb.y0, pb.observed_data, pb.observed_idx] = ...
    loadStateData(pb.dataDir, pb.dataFile, pb.nstates);
pb.m = numel(pb.times);

% --- run settings, from the C side ---------------------------------------
pb.settings = st;
pb.name = st.name;
pb.alp = st.alp;
pb.maxeval = st.maxeval;

opts = cuqdyn_default_options(pb.n_params);
opts.uq.alp = pb.alp;
opts.meigo.maxeval = pb.maxeval;
opts.meigo.iterprint = 0;
opts.ode.RelTol = st.rtol;
if numel(unique(st.atol)) == 1
    opts.ode.AbsTol = st.atol(1);
else
    opts.ode.AbsTol = st.atol(:).';
end
if ~isempty(char(o.LocalSolver))
    opts.meigo.local.solver = char(o.LocalSolver);
    opts.meigo.local.tol = 2;
end

% The residual model is the MATLAB definition's. A sigma derived from the
% reference trajectory is integrated with ode15s whatever 'Solver' says: it is
% part of the problem statement, not of the pipeline under test.
[ode_options, ~] = cuqdyn_odeset_from_options(opts.ode);
[~, pb.Y_true] = ode15s(@(t, y) pb.dynamics(t, y, pb.true_params), pb.times, pb.y0, ode_options);
opts.cost = cuqdyn_cost_options_from_problem(problem, pb.Y_true, pb.observed_idx);
% A known sigma is a number the C side reads from its XML, while the MATLAB
% definition derives it by a convention (a percentage of the mean reference
% trajectory) that the example runners do not all share. Both sides must weigh
% the residuals alike or every layer fails for a reason unrelated to the port,
% so the XML value is used; compare_sides reports how far the derivation is.
pb.sigma_matlab = [];
if strcmpi(char(opts.cost.residual_model), 'known_sigma')
    pb.sigma_matlab = opts.cost.sigma(:).';
    if isfield(st, 'sigma') && numel(st.sigma) == numel(pb.sigma_matlab)
        opts.cost.sigma = reshape(st.sigma, size(opts.cost.sigma));
    end
end

switch lower(char(o.Solver))
    case 'ode15s'
    case 'cvodes'
        opts.ode.solver = @cvodes_solver;
    otherwise
        error('load_problem:solver', 'Unknown Solver "%s" (ode15s|cvodes).', char(o.Solver));
end
cuqdyn_set_ode_options(opts.ode);
[~, pb.ode_opts] = cuqdyn_get_ode_options();

pb.opts = opts;
pb.meigo_opts = opts.meigo;
pb.meigo_opts.cost_opts = opts.cost;
% The LOO loop must not run under parfor, or the rng stream is split across
% workers and a seeded run is not repeatable.
pb.meigo_opts.parallel.use_parallel = false;
pb.cost_opts = cuqdyn_fill_cost_options(opts.cost);

% --- what both sides define twice ------------------------------------------
pb.checks = compare_sides(pb, st);
bad = pb.checks(~[pb.checks.ok] & ~[pb.checks.warning]);
if o.Strict && ~isempty(bad)
    msg = '';
    for i = 1:numel(bad)
        msg = [msg sprintf('  %s: C side %s, MATLAB side %s\n', bad(i).report{:})]; %#ok<AGROW>
    end
    error('load_problem:mismatch', ...
        'The C and MATLAB definitions of "%s" disagree:\n%s', pb.name, msg);
end
end

%% ------------------------------------------------------------------ local --

function v = first_nonempty(varargin)
v = '';
for i = 1:nargin
    if ~isempty(varargin{i}), v = varargin{i}; return; end
end
end

function v = field_or(st, name)
v = '';
if isfield(st, name), v = char(string(st.(name))); end
end

function st = read_settings(path)
fid = fopen(path, 'r');
if fid < 0, error('load_problem:settings', 'cannot read %s', path); end
cleanup = onCleanup(@() fclose(fid));
st = struct();
line = fgetl(fid);
while ischar(line)
    tok = strsplit(strtrim(line));
    if numel(tok) >= 2
        val = str2double(tok(2:end));
        if any(isnan(val)) && ~all(strcmpi(tok(2:end), 'nan'))
            st.(tok{1}) = strjoin(tok(2:end), ' ');
        else
            st.(tok{1}) = val;
        end
    end
    line = fgetl(fid);
end
for f = {'name', 'n_states', 'n_params', 'm', 'times', 'y0', 'observed_idx', ...
        'alp', 'rtol', 'atol', 'maxeval', 'lb', 'ub', 'x0', 'residual_model', ...
        'matlab_problem'}
    if ~isfield(st, f{1})
        error('load_problem:settings', '%s: missing "%s"', path, f{1});
    end
end
end

function checks = compare_sides(pb, st)
% The XMLs carry rounded decimal text, hence a relative tolerance rather than
% equality; 1e-9 is far below anything that changes a result.
tol = 1e-9;
checks = struct('field', {}, 'ok', {}, 'warning', {}, 'report', {});
    function add(field, c_val, m_val, rel_tol, warning)
        c_val = c_val(:).'; m_val = m_val(:).';
        ok = isequal(size(c_val), size(m_val)) && ...
            all(abs(c_val - m_val) <= rel_tol * max(abs(m_val), realmin));
        r = {field, mat2str(c_val, 12), mat2str(m_val, 12)};
        checks(end + 1) = struct('field', field, 'ok', ok, 'warning', warning, 'report', {r});
    end
add('n_states', st.n_states, pb.nstates, tol, false);
add('n_params', st.n_params, pb.n_params, tol, false);
add('m (time points)', st.m, pb.m, tol, false);
add('times', st.times, pb.times, tol, false);
add('y0', st.y0, pb.y0, tol, false);
add('observed_idx', st.observed_idx, pb.observed_idx, tol, false);
add('lower bounds', st.lb, pb.lb_params, tol, false);
add('upper bounds', st.ub, pb.ub_params, tol, false);
add('initial point', st.x0, pb.guess_params, tol, false);
m_model = lower(char(pb.cost_opts.residual_model));
ok = strcmpi(st.residual_model, m_model);
checks(end + 1) = struct('field', 'residual_model', 'ok', ok, 'warning', false, ...
    'report', {{'residual_model', st.residual_model, m_model}});
if strcmp(m_model, 'known_sigma') && isfield(st, 'sigma')
    % Derived from an integrated trajectory: integration accuracy, not 1e-9.
    add('sigma (the C value is used)', st.sigma, pb.sigma_matlab, 1e-6, true);
end
end
