function write_matrix(path, M)
%WRITE_MATRIX The validation/ plain-text matrix format: "rows cols" then %.17g rows.
fid = fopen(path, 'w');
if fid < 0, error('write_matrix:io', 'cannot write %s', path); end
fprintf(fid, '%d %d\n', size(M, 1), size(M, 2));
for i = 1:size(M, 1)
    fprintf(fid, '%.17g ', M(i, :));
    fprintf(fid, '\n');
end
fclose(fid);
end
