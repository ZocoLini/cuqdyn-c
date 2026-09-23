function M = read_section_matrix(path, name)
%READ_SECTION_MATRIX Read one 2-D array section of a packed reference file.
%
%   M = read_section_matrix(path, name)
%
% The section body is "rows cols" followed by the rows (write_section_matrix).
[names, bodies] = read_sections(path);
k = find(strcmp(names, name), 1);
if isempty(k)
    error('read_section_matrix:missing', 'no section [%s] in %s', name, path);
end
values = sscanf(bodies{k}, '%f');
rows = values(1);
cols = values(2);
if numel(values) ~= 2 + rows * cols
    error('read_section_matrix:short', '[%s] in %s: %d values for a %dx%d array', ...
        name, path, numel(values) - 2, rows, cols);
end
M = reshape(values(3:end), cols, rows).';
end
