function write_section_matrix(fid, name, M)
%WRITE_SECTION_MATRIX Append one array section to an open reference file.
%
%   [name]
%   rows cols
%   <row-major values, %.17g>
%
% The body is the project's plain matrix format; the header line is what
% makes it one section of a packed reference file (validation/c/refio.h reads
% it back).
fprintf(fid, '[%s]\n', name);
fprintf(fid, '%d %d\n', size(M, 1), size(M, 2));
for i = 1:size(M, 1)
    fprintf(fid, '%.17g ', M(i, :));
    fprintf(fid, '\n');
end
end
