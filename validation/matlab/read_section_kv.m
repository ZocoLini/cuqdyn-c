function value = read_section_kv(path, name, key)
%READ_SECTION_KV Look a key up in a "key value" section of a packed reference file.
%
%   value = read_section_kv(path, name, key)
%
% Returns the value as text ('' when the section or the key is absent); the
% caller converts it. A value keeps its inner blanks.
value = '';
[names, bodies] = read_sections(path);
k = find(strcmp(names, name), 1);
if isempty(k)
    return;
end
lines = strsplit(bodies{k}, newline);
for i = 1:numel(lines)
    tok = regexp(strtrim(lines{i}), '^(\S+)\s+(.*)$', 'tokens', 'once');
    if ~isempty(tok) && strcmp(tok{1}, key)
        value = tok{2};
        return;
    end
end
end
