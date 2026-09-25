function write_section_kv(fid, name, kv)
%WRITE_SECTION_KV Append one "key value" section to an open reference file.
%
%   [name]
%   key value
%   ...
%
% kv is an n x 2 cell array. Numbers are written with %.17g, infinities as
% inf / -inf (validation/c/refio.h and test_golden.c read them back), text as
% it is.
fprintf(fid, '[%s]\n', name);
for i = 1:size(kv, 1)
    v = kv{i, 2};
    if ischar(v) || isstring(v)
        fprintf(fid, '%s %s\n', kv{i, 1}, char(v));
    elseif isinf(v)
        if v > 0
            fprintf(fid, '%s inf\n', kv{i, 1});
        else
            fprintf(fid, '%s -inf\n', kv{i, 1});
        end
    else
        fprintf(fid, '%s %.17g\n', kv{i, 1}, v);
    end
end
end
