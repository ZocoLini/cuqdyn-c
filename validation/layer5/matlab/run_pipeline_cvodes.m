function run_pipeline_cvodes(model, base_seed, out_dir)
%RUN_PIPELINE_CVODES The MATLAB pipeline of layer 5: MEIGO + CVODES, seeded per launch.
%
%   run_pipeline_cvodes('lv2', 20260917, 'validation/layer5/matlab/lv2')
%
% Same problem, same seeds and same integrator family as the C run driven by
% meigo_server. Writes the layer-4 artefact set, params_median.txt and the
% evaluation traces into out_dir.

pb = problem_def(model);
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

ens = loo_ensemble_seeded(pb, base_seed, out_dir);
[UQ_lower, UQ_upper, Cov_p, std_y, fimDiagnostics] = uq_cvodes( ...
    ens.media_tot, pb.observed_data, pb.observed_idx, pb.y0, pb.times, ens.parameters_init, ...
    pb.nstates, pb.n_params, ens.m, ens.UQ_lower_obs, ens.UQ_upper_obs, pb.alp, ...
    pb.dynamics, pb.cost_opts, pb.ode_opts, struct());

write_matrix(fullfile(out_dir, 'theta_hat.txt'), ens.parameters_init(:));
write_matrix(fullfile(out_dir, 'params_median.txt'), median(ens.loo_params, 1).');
write_matrix(fullfile(out_dir, 'loo_params.txt'), ens.loo_params);
write_matrix(fullfile(out_dir, 'resid_loo.txt'), ens.resid_loo);
write_matrix(fullfile(out_dir, 'media_tot.txt'), ens.media_tot);
write_matrix(fullfile(out_dir, 'q_low.txt'), UQ_lower);
write_matrix(fullfile(out_dir, 'q_up.txt'), UQ_upper);
write_matrix(fullfile(out_dir, 'cov_p.txt'), Cov_p);
write_matrix(fullfile(out_dir, 'std_y.txt'), std_y);
fid = fopen(fullfile(out_dir, 'meta.txt'), 'w');
fprintf(fid, 'model %s\nbase_seed %d\nmaxeval %d\nfim_rank %d\nfim_condition %.6g\nmatlab_version %s\n', ...
    model, base_seed, pb.maxeval, fimDiagnostics.rank, fimDiagnostics.condition_number, version);
fclose(fid);
fprintf('run_pipeline_cvodes: %s written to %s\n', model, out_dir);
end
