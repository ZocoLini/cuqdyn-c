function optionTable = save_run_options(resultDir, opts, baseName)
%SAVE_RUN_OPTIONS Print and save run options for reproducibility.

if nargin < 1 || isempty(resultDir)
    resultDir = pwd;
end
if nargin < 2 || isempty(opts)
    opts = struct();
end
if nargin < 3 || isempty(baseName)
    baseName = 'run_options';
end
if ~exist(resultDir, 'dir')
    mkdir(resultDir);
end

optionTable = flatten_options(opts);

fprintf('\n=== CUQDyn run options ===\n');
disp(optionTable);

save(fullfile(resultDir, [char(baseName) '.mat']), 'opts');
try
    writetable(optionTable, fullfile(resultDir, [char(baseName) '.xlsx']), ...
        'Sheet', 'Options');
catch ME
    warning('save_run_options:ExcelWriteFailed', ...
        'Could not write %s.xlsx: %s', char(baseName), ME.message);
end

end

function optionTable = flatten_options(s)
names = {};
values = {};
[names, values] = local_flatten(s, '', names, values);
optionTable = table(names(:), values(:), ...
    'VariableNames', {'Option', 'Value'});
end

function [names, values] = local_flatten(s, prefix, names, values)
if ~isstruct(s)
    names{end+1} = prefix;
    values{end+1} = local_to_string(s);
    return;
end

fields = fieldnames(s);
for i = 1:numel(fields)
    f = fields{i};
    if isempty(prefix)
        key = f;
    else
        key = [prefix '.' f];
    end
    v = s.(f);
    if isstruct(v)
        [names, values] = local_flatten(v, key, names, values);
    else
        names{end+1} = key; %#ok<AGROW>
        values{end+1} = local_to_string(v); %#ok<AGROW>
    end
end
end

function txt = local_to_string(v)
if isempty(v)
    txt = '';
elseif ischar(v)
    txt = v;
elseif isstring(v)
    txt = char(strjoin(v(:)', ', '));
elseif isnumeric(v) || islogical(v)
    if isscalar(v)
        txt = char(string(v));
    else
        txt = mat2str(v);
    end
elseif isa(v, 'function_handle')
    txt = func2str(v);
else
    txt = char(string(v));
end
end
