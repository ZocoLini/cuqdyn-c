function [names, bodies] = read_sections(path)
%READ_SECTIONS Split a packed reference file into its "[name]" sections.
%
%   [names, bodies] = read_sections(path)
%
% names{k} is the k-th section name, bodies{k} the text between its header
% line and the next header (or the end of the file), one line per row, each
% terminated by a newline. A missing file gives two empty cell arrays, so a
% generator can merge into a file that does not exist yet. Text before the
% first header is ignored.
names = {};
bodies = {};
if ~exist(path, 'file')
    return;
end
txt = fileread(path);
txt = strrep(txt, sprintf('\r\n'), newline);
lines = strsplit(txt, newline, 'CollapseDelimiters', false);
if ~isempty(lines) && isempty(lines{end})
    lines(end) = [];    % the final newline
end
tokens = regexp(lines, '^\[(.+)\]\s*$', 'tokens', 'once');
is_header = ~cellfun(@isempty, tokens);
starts = find(is_header);
ends = [starts(2:end) - 1, numel(lines)];
names = cell(1, numel(starts));
bodies = cell(1, numel(starts));
for k = 1:numel(starts)
    names{k} = tokens{starts(k)}{1};
    body_lines = lines(starts(k) + 1:ends(k));
    if isempty(body_lines)
        bodies{k} = '';
    else
        bodies{k} = [strjoin(body_lines, newline), newline];
    end
end
end
