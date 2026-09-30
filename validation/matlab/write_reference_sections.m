function write_reference_sections(path, names, bodies)
%WRITE_REFERENCE_SECTIONS Merge sections into references/<name>.txt.
%
% Merge the sections just produced into the reference file of the problem:
% a section that was regenerated replaces the old one, the others are kept,
% and the file is written in the canonical order so that a regeneration of
% one layer leaves a minimal diff.
order = {'meta', 'times', 'y0', 'observed_idx', 'sigma', 'truth', ...
    'theta_fixed', 'traj', 'sens', ...
    'theta_hat', 'loo_params', 'resid_loo', 'media_tot', 'q_low', 'q_up', ...
    'cov_p', 'std_y', 'observed_data', 'media_matrix', 'meta4', 'evals'};
[old_names, old_bodies] = read_sections(path);
all_names = [old_names, names];
all_bodies = [old_bodies, bodies];
known = [order, setdiff(all_names, order, 'stable')];
fid = fopen(path, 'w');
if fid < 0, error('write_reference_sections:io', 'cannot write %s', path); end
for i = 1:numel(known)
    k = find(strcmp(all_names, known{i}), 1, 'last');   % the new one wins
    if isempty(k), continue; end
    fprintf(fid, '[%s]\n', known{i});
    fprintf(fid, '%s', all_bodies{k});
end
fclose(fid);
end
