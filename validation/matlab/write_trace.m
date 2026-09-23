function write_trace(path, rows)
%WRITE_TRACE Rows of "theta... J" at %.17g, no header - the layer-5 trace format.
%
% Traces are accumulated in memory during a MEIGO launch and written afterwards:
% MEIGO closes every open file (fclose all) while it runs.
fid = fopen(path, 'w');
if fid < 0, error('write_trace:io', 'cannot write %s', path); end
for i = 1:size(rows, 1)
    fprintf(fid, '%.17g ', rows(i, 1:end-1));
    fprintf(fid, '%.17g\n', rows(i, end));
end
fclose(fid);
end
