function write_expected_output()
%WRITE_EXPECTED_OUTPUT Emit the MATLAB reference file test_cuqdyn_algo.c reads.
%
% Runs (or reuses) the seeded layer-3 LV2 baseline and writes
%
%     example-files/lv2_partobs_expected_output.txt
%     tests/data/lv2_partobs_expected_output.txt
%
% in the same labelled-section format the CLI uses for cuqdyn-results.txt.
% When the file is present, the lv2_partobs case in tests/test_cuqdyn_algo.c
% compares the full C pipeline against it with generous mean-error margins
% (two independent eSS runs can never agree tightly). When absent, the test
% keeps passing on its structural asserts alone, so nothing breaks for
% people who have not generated the reference yet.
%
% Only needs running once per MATLAB-side change; commit the two files.

here = fileparts(mfilename('fullpath'));
repo = fullfile(here, '..', '..');
l4 = fullfile(here, 'matlab', 'lv2', 'layer3');

if ~exist(fullfile(l4, 'theta_hat.txt'), 'file')
    fprintf('No layer-3 export found; running gen_baseline(''lv2'', [2 3]) first...\n');
    gen_baseline('lv2', [2 3]);
end

theta_hat = read_m(fullfile(l4, 'theta_hat.txt'));
loo_params = read_m(fullfile(l4, 'loo_params.txt'));
q_low = read_m(fullfile(l4, 'q_low.txt'));
q_up = read_m(fullfile(l4, 'q_up.txt'));
media_tot = read_m(fullfile(l4, 'media_tot.txt'));

% The C pipeline reports the median over the LOO ensemble as [Params].
params_median = median(loo_params, 1).';

dests = { ...
    fullfile(repo, 'example-files', 'lv2_partobs_expected_output.txt'), ...
    fullfile(repo, 'tests', 'data', 'lv2_partobs_expected_output.txt')};

for d = 1:numel(dests)
    fid = fopen(dests{d}, 'w');
    if fid < 0, error('write_expected_output:io', 'cannot write %s', dests{d}); end

    write_vector(fid, 'Params', params_median);
    write_vector(fid, 'ParamsInit', theta_hat);
    write_matrix(fid, 'Q_low', q_low);
    write_matrix(fid, 'Q_up', q_up);
    write_matrix(fid, 'MediaTot', media_tot);

    fclose(fid);
    fprintf('Wrote %s\n', dests{d});
end
end

function M = read_m(path)
fid = fopen(path, 'r');
if fid < 0, error('write_expected_output:io', 'cannot read %s', path); end
dims = fscanf(fid, '%d', 2);
M = fscanf(fid, '%f', [dims(2), dims(1)]).';
fclose(fid);
end

function write_vector(fid, name, v)
fprintf(fid, '[%s]\n%d\n', name, numel(v));
fprintf(fid, '%.17g ', v);
fprintf(fid, '\n');
end

function write_matrix(fid, name, M)
fprintf(fid, '[%s]\n%d %d\n', name, size(M, 1), size(M, 2));
for i = 1:size(M, 1)
    fprintf(fid, '%.17g ', M(i, :));
    fprintf(fid, '\n');
end
end
