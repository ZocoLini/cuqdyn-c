/*
 * Layers 2 and 3 of the MATLAB-baseline comparison.
 *
 * Layer 2: integrate the ODE and its sensitivities at FIXED parameters and
 *          compare against MATLAB's ode15s trajectory and complex-step
 *          sensitivities. No optimiser on either side.
 * Layer 3: take theta_hat and the whole LOO ensemble from a seeded MATLAB
 *          run and replay ONLY the UQ stage in C (conformal_bands +
 *          delta_method_bands), so the band mathematics is compared on
 *          identical inputs, free of eSS noise.
 *
 * The harness only calls functions the cuqdyn-c library already exports;
 * the library itself is untouched.
 *
 *   ./test_baseline <baseline_dir> <cuqdyn_config.xml> <data_file>
 *
 * baseline_dir is one model directory written by gen_baseline.m
 * (e.g. validation/baseline/matlab/lv2). Missing layer subdirectories are
 * skipped; if neither exists the exit code is 77 so ctest reports SKIP.
 * Otherwise the exit code is the number of failing comparisons.
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "cuqdyn.h"
#include "data_reader.h"
#include "functions.h"
#include "ode_solver.h"
#include "sensitivity.h"
#include "uq_bands.h"

static int g_failures = 0;
static int g_checks = 0;

/* ------------------------------------------------------------------ io -- */

static int file_exists(const char *path)
{
    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        return 0;
    }
    fclose(f);
    return 1;
}

static SUNMatrix read_matrix(const char *path)
{
    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        fprintf(stderr, "ERROR: cannot open %s\n", path);
        exit(2);
    }

    long rows, cols;
    if (fscanf(f, "%ld %ld", &rows, &cols) != 2)
    {
        fprintf(stderr, "ERROR: bad header in %s\n", path);
        exit(2);
    }

    SUNMatrix m = NewDenseMatrix(rows, cols);
    for (long i = 0; i < rows; ++i)
    {
        for (long j = 0; j < cols; ++j)
        {
            double v;
            if (fscanf(f, "%lf", &v) != 1)
            {
                fprintf(stderr, "ERROR: short read in %s at (%ld,%ld)\n", path, i, j);
                exit(2);
            }
            SM_ELEMENT_D(m, i, j) = v;
        }
    }
    fclose(f);
    return m;
}

static double read_kv_double(const char *path, const char *key, double fallback)
{
    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        return fallback;
    }

    char k[256], v[256];
    double out = fallback;
    while (fscanf(f, "%255s %255s", k, v) == 2)
    {
        if (strcmp(k, key) == 0)
        {
            out = atof(v);
            break;
        }
    }
    fclose(f);
    return out;
}

/* ------------------------------------------------------------ compare -- */

static void report(const char *what, double max_abs, double max_rel, double tol)
{
    const int ok = max_rel <= tol && !isnan(max_rel);
    g_checks++;
    if (!ok)
    {
        g_failures++;
    }
    printf("  %-28s max_abs=%.3e  max_rel=%.3e  tol=%.1e  %s\n", what, max_abs, max_rel, tol,
           ok ? "ok" : "**FAIL**");
}

/*
 * Max-scaled relative difference, like test_golden: |got - exp| scaled by the
 * largest magnitude of the expected block, so entries legitimately near zero
 * do not blow the ratio up.
 */
typedef struct
{
    double max_abs;
    double scale;
} Diff;

static void diff_init(Diff *d) { d->max_abs = 0.0; d->scale = 0.0; }

static void diff_add(Diff *d, double got, double expected)
{
    const double delta = fabs(got - expected);
    if (delta > d->max_abs)
    {
        d->max_abs = delta;
    }
    if (fabs(expected) > d->scale)
    {
        d->scale = fabs(expected);
    }
}

static double diff_rel(const Diff *d) { return d->max_abs / (d->scale > 1e-300 ? d->scale : 1.0); }

/* ------------------------------------------------------------- layer 2 -- */

static void run_layer2(const char *dir, const CuqdynData *data, const CuqdynConf *conf, double tol_traj,
                       double tol_sens)
{
    char path[1024];

    snprintf(path, sizeof(path), "%s/layer2/theta_fixed.txt", dir);
    if (!file_exists(path))
    {
        printf("layer 2: not present, skipping\n");
        return;
    }
    printf("layer 2: ODE + sensitivities at fixed parameters\n");

    SUNMatrix theta_m = read_matrix(path);
    const long n_params = SM_ROWS_D(theta_m);
    N_Vector theta = New_Serial(n_params);
    for (long i = 0; i < n_params; ++i)
    {
        NV_Ith_S(theta, i) = SM_ELEMENT_D(theta_m, i, 0);
    }
    SUNMatDestroy(theta_m);

    snprintf(path, sizeof(path), "%s/layer2/traj.txt", dir);
    SUNMatrix traj_exp = read_matrix(path); /* m x nstates */
    const long m = SM_ROWS_D(traj_exp);
    const long n_states = SM_COLUMNS_D(traj_exp);
    const sunrealtype t0 = NV_Ith_S(data->times, 0);

    if (m != NV_LENGTH_S(data->times) || n_states != data->n_states)
    {
        printf("  %-28s export is %ldx%ld but the data file has m=%ld, n_states=%ld  **FAIL**\n",
               "layer2 shape", m, n_states, (long) NV_LENGTH_S(data->times), data->n_states);
        g_checks++;
        g_failures++;
        SUNMatDestroy(traj_exp);
        N_VDestroy(theta);
        return;
    }

    /* --- trajectory --- */
    TransposedStates got = solve_ode(theta, data->initial_values, t0, data->times);
    if (got == NULL)
    {
        printf("  %-28s solve_ode returned NULL  **FAIL**\n", "trajectory");
        g_checks++;
        g_failures++;
    }
    else
    {
        Diff d;
        diff_init(&d);
        for (long i = 0; i < m; ++i)
        {
            for (long j = 0; j < n_states; ++j)
            {
                diff_add(&d, SM_ELEMENT_D(got, j, i), SM_ELEMENT_D(traj_exp, i, j));
            }
        }
        report("trajectory", d.max_abs, diff_rel(&d), tol_traj);
        SUNMatDestroy(got);
    }

    /* --- sensitivities --- */
    snprintf(path, sizeof(path), "%s/layer2/sens.txt", dir);
    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        fprintf(stderr, "ERROR: cannot open %s\n", path);
        exit(2);
    }
    long sm, sn, sp;
    if (fscanf(f, "%ld %ld %ld", &sm, &sn, &sp) != 3 || sm != m || sn != n_states || sp != n_params)
    {
        fprintf(stderr, "ERROR: sens.txt header disagrees with traj.txt/theta\n");
        exit(2);
    }

    TransposedStates states = NULL;
    Sensitivities sens = {0};
    if (solve_ode_with_sensitivities(theta, data->initial_values, t0, data->times, &states, &sens) != 0)
    {
        printf("  %-28s solve_ode_with_sensitivities failed  **FAIL**\n", "sensitivities");
        g_checks++;
        g_failures++;
        fclose(f);
        SUNMatDestroy(traj_exp);
        N_VDestroy(theta);
        return;
    }
    SUNMatDestroy(states);

    /* One comparison per parameter: each dy/dtheta_k block has its own scale
     * (NF-kB spans ~10 orders of magnitude across parameters). */
    for (long k = 0; k < n_params; ++k)
    {
        Diff d;
        diff_init(&d);
        for (long i = 0; i < m; ++i)
        {
            for (long j = 0; j < n_states; ++j)
            {
                double expected;
                if (fscanf(f, "%lf", &expected) != 1)
                {
                    fprintf(stderr, "ERROR: short read in sens.txt (param %ld)\n", k);
                    exit(2);
                }
                diff_add(&d, sensitivity_at(sens, j, i, (int) k), expected);
            }
        }
        char label[64];
        snprintf(label, sizeof(label), "sens dtheta_%ld", k + 1);
        report(label, d.max_abs, diff_rel(&d), tol_sens);
    }
    fclose(f);

    destroy_sensitivities(sens);
    SUNMatDestroy(traj_exp);
    N_VDestroy(theta);
    (void) conf;
}

/* ------------------------------------------------------------- layer 3 -- */

static int is_observed(const int *observed_idx, const int n_obs, const long state)
{
    for (int j = 0; j < n_obs; ++j)
    {
        if (observed_idx[j] == state)
        {
            return 1;
        }
    }
    return 0;
}

static void run_layer3(const char *dir, const CuqdynData *data, const CuqdynConf *conf, double tol_conf,
                       double tol_delta, double tol_covp)
{
    char path[1024];

    snprintf(path, sizeof(path), "%s/layer3/theta_hat.txt", dir);
    if (!file_exists(path))
    {
        printf("layer 3: not present, skipping\n");
        return;
    }
    printf("layer 3: UQ stage replayed on the MATLAB ensemble\n");

    const long n_states = conf->ode_expr.y_count;
    const long n_params = conf->ode_expr.p_count;
    const long m = NV_LENGTH_S(data->times);
    const int n_obs = data->n_obs;
    const sunrealtype t0 = NV_Ith_S(data->times, 0);

    /* --- cross-checks: the XML and the MATLAB export must describe the same
     *     problem, otherwise every comparison below is meaningless --- */
    snprintf(path, sizeof(path), "%s/meta.txt", dir);
    const double alp_matlab = read_kv_double(path, "alp", NAN);
    if (fabs(alp_matlab - conf->alp) > 1e-12)
    {
        printf("  %-28s XML alp=%g, MATLAB alp=%g  **FAIL**\n", "alp agreement", conf->alp, alp_matlab);
        g_checks++;
        g_failures++;
        return;
    }

    snprintf(path, sizeof(path), "%s/observed_idx.txt", dir);
    SUNMatrix obs_idx_m = read_matrix(path); /* 1-based, from MATLAB */
    if (SM_ROWS_D(obs_idx_m) != n_obs)
    {
        printf("  %-28s data file has %d observed states, MATLAB %ld  **FAIL**\n", "observed_idx", n_obs,
               SM_ROWS_D(obs_idx_m));
        g_checks++;
        g_failures++;
        SUNMatDestroy(obs_idx_m);
        return;
    }
    for (int j = 0; j < n_obs; ++j)
    {
        if ((long) SM_ELEMENT_D(obs_idx_m, j, 0) - 1 != data->observed_idx[j])
        {
            printf("  %-28s mismatch at %d  **FAIL**\n", "observed_idx", j);
            g_checks++;
            g_failures++;
            SUNMatDestroy(obs_idx_m);
            return;
        }
    }
    SUNMatDestroy(obs_idx_m);

    /* sigma in the XML must equal the sigma MATLAB derived from the true
     * trajectory - it is how the C run weights residuals. */
    snprintf(path, sizeof(path), "%s/sigma.txt", dir);
    if (file_exists(path) && conf->cost.residual_model == RESIDUAL_MODEL_KNOWN_SIGMA)
    {
        SUNMatrix sigma_m = read_matrix(path);
        Diff d;
        diff_init(&d);
        for (int j = 0; j < n_obs && j < SM_ROWS_D(sigma_m); ++j)
        {
            const double w = cuqdyn_residual_weight(&conf->cost, j);
            diff_add(&d, 1.0 / w, SM_ELEMENT_D(sigma_m, j, 0));
        }
        report("sigma XML vs MATLAB", d.max_abs, diff_rel(&d), 1e-9);
        SUNMatDestroy(sigma_m);
    }

    if (conf->time_scaling != 1.0)
    {
        printf("  %-28s time_scaling=%g unsupported by the harness  **FAIL**\n", "time_scaling",
               conf->time_scaling);
        g_checks++;
        g_failures++;
        return;
    }

    /* --- load the MATLAB ensemble --- */
    snprintf(path, sizeof(path), "%s/layer3/theta_hat.txt", dir);
    SUNMatrix theta_m = read_matrix(path);
    N_Vector theta_hat = New_Serial(n_params);
    for (long i = 0; i < n_params; ++i)
    {
        NV_Ith_S(theta_hat, i) = SM_ELEMENT_D(theta_m, i, 0);
    }
    SUNMatDestroy(theta_m);

    snprintf(path, sizeof(path), "%s/layer3/loo_params.txt", dir);
    SUNMatrix loo_params = read_matrix(path); /* (m-1) x n_params */

    snprintf(path, sizeof(path), "%s/layer3/resid_loo.txt", dir);
    SUNMatrix resid_matlab = read_matrix(path); /* (m-1) x n_obs */

    /* C convention: m rows, row 0 unused. */
    SUNMatrix resid_loo = NewDenseMatrix(m, n_obs);
    for (long i = 0; i < m; ++i)
    {
        for (int j = 0; j < n_obs; ++j)
        {
            SM_ELEMENT_D(resid_loo, i, j) = i == 0 ? 0.0 : SM_ELEMENT_D(resid_matlab, i - 1, j);
        }
    }
    SUNMatDestroy(resid_matlab);

    /* media_matrix: (m-1) blocks of m x nstates -> transposed per-LOO copies */
    snprintf(path, sizeof(path), "%s/layer3/media_matrix.txt", dir);
    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        fprintf(stderr, "ERROR: cannot open %s\n", path);
        exit(2);
    }
    long n_loo, mm, nn;
    if (fscanf(f, "%ld %ld %ld", &n_loo, &mm, &nn) != 3 || n_loo != m - 1 || mm != m || nn != n_states)
    {
        fprintf(stderr, "ERROR: media_matrix.txt header disagrees with the problem shape\n");
        exit(2);
    }

    MatrixArray media_matrix = create_matrix_array(n_loo);
    SUNMatrix block = NewDenseMatrix(n_states, m);
    for (long k = 0; k < n_loo; ++k)
    {
        for (long i = 0; i < m; ++i)
        {
            for (long j = 0; j < n_states; ++j)
            {
                double v;
                if (fscanf(f, "%lf", &v) != 1)
                {
                    fprintf(stderr, "ERROR: short read in media_matrix.txt (block %ld)\n", k);
                    exit(2);
                }
                SM_ELEMENT_D(block, j, i) = v;
            }
        }
        matrix_array_set_index(media_matrix, k, block); /* copies */
    }
    SUNMatDestroy(block);
    fclose(f);

    snprintf(path, sizeof(path), "%s/layer3/media_tot.txt", dir);
    SUNMatrix media_tot_row = read_matrix(path); /* m x nstates */
    TransposedStates media_tot = NewDenseMatrix(n_states, m);
    for (long i = 0; i < m; ++i)
    {
        for (long j = 0; j < n_states; ++j)
        {
            SM_ELEMENT_D(media_tot, j, i) = SM_ELEMENT_D(media_tot_row, i, j);
        }
    }
    SUNMatDestroy(media_tot_row);

    snprintf(path, sizeof(path), "%s/layer3/q_low.txt", dir);
    SUNMatrix q_low_exp = read_matrix(path);
    if (SM_ROWS_D(q_low_exp) != m || SM_COLUMNS_D(q_low_exp) != n_states)
    {
        fprintf(stderr, "ERROR: q_low.txt is %ldx%ld, expected %ldx%ld\n", SM_ROWS_D(q_low_exp),
                SM_COLUMNS_D(q_low_exp), m, n_states);
        exit(2);
    }
    snprintf(path, sizeof(path), "%s/layer3/q_up.txt", dir);
    SUNMatrix q_up_exp = read_matrix(path);
    snprintf(path, sizeof(path), "%s/layer3/cov_p.txt", dir);
    SUNMatrix cov_p_exp = read_matrix(path);
    snprintf(path, sizeof(path), "%s/layer3/std_y.txt", dir);
    SUNMatrix std_y_exp = read_matrix(path); /* m x nstates */

    /* --- replay the UQ stage exactly as cuqdyn_algo does --- */
    SUNMatrix q_low = NewDenseMatrix(m, n_states);
    SUNMatrix q_up = NewDenseMatrix(m, n_states);
    for (long k = 0; k < n_states; ++k)
    {
        SM_ELEMENT_D(q_low, 0, k) = NV_Ith_S(data->initial_values, k);
        SM_ELEMENT_D(q_up, 0, k) = NV_Ith_S(data->initial_values, k);
    }

    conformal_bands(media_matrix, resid_loo, data->observed_idx, n_obs, conf->alp, q_low, q_up);

    /* Conformal comparison first, so a delta failure cannot mask it. */
    {
        Diff dl, du;
        diff_init(&dl);
        diff_init(&du);
        for (long k = 0; k < n_states; ++k)
        {
            if (!is_observed(data->observed_idx, n_obs, k))
            {
                continue;
            }
            for (long i = 1; i < m; ++i)
            {
                diff_add(&dl, SM_ELEMENT_D(q_low, i, k), SM_ELEMENT_D(q_low_exp, i, k));
                diff_add(&du, SM_ELEMENT_D(q_up, i, k), SM_ELEMENT_D(q_up_exp, i, k));
            }
        }
        report("conformal q_low", dl.max_abs, diff_rel(&dl), tol_conf);
        report("conformal q_up", du.max_abs, diff_rel(&du), tol_conf);
    }

    SUNMatrix cov_p = NULL;
    SUNMatrix std_y = NULL;
    SUNMatrix q_low_alt = NULL;
    SUNMatrix q_up_alt = NULL;

    if (delta_method_bands(theta_hat, data->initial_values, t0, data->times, media_tot, data->observed_data,
                           data->observed_idx, n_obs, loo_params, q_low, q_up, &cov_p, &std_y, &q_low_alt,
                           &q_up_alt) != 0)
    {
        printf("  %-28s delta_method_bands failed  **FAIL**\n", "delta bands");
        g_checks++;
        g_failures++;
    }
    else
    {
        int n_hidden = 0;
        Diff dl, du;
        diff_init(&dl);
        diff_init(&du);
        for (long k = 0; k < n_states; ++k)
        {
            if (is_observed(data->observed_idx, n_obs, k))
            {
                continue;
            }
            n_hidden++;
            for (long i = 1; i < m; ++i)
            {
                diff_add(&dl, SM_ELEMENT_D(q_low, i, k), SM_ELEMENT_D(q_low_exp, i, k));
                diff_add(&du, SM_ELEMENT_D(q_up, i, k), SM_ELEMENT_D(q_up_exp, i, k));
            }
        }
        if (n_hidden > 0)
        {
            report("delta q_low (hidden)", dl.max_abs, diff_rel(&dl), tol_delta);
            report("delta q_up  (hidden)", du.max_abs, diff_rel(&du), tol_delta);
        }

        /* Element-wise cov_p agreement is only meaningful while the FIM is
         * well conditioned: near singularity the weak directions carry
         * regularisation artefacts on both sides (see validation/README.md),
         * which is why tol.txt can widen this one independently. The bands
         * and std_y stay comparable regardless, since weak directions barely
         * project onto the trajectory. */
        Diff dc;
        diff_init(&dc);
        for (long i = 0; i < n_params; ++i)
        {
            for (long j = 0; j < n_params; ++j)
            {
                diff_add(&dc, SM_ELEMENT_D(cov_p, i, j), SM_ELEMENT_D(cov_p_exp, i, j));
            }
        }
        report("cov_p", dc.max_abs, diff_rel(&dc), tol_covp);

        Diff ds;
        diff_init(&ds);
        for (long i = 0; i < m; ++i)
        {
            for (long j = 0; j < n_states; ++j)
            {
                /* C std_y is n_states x m (transposed), MATLAB m x nstates */
                diff_add(&ds, SM_ELEMENT_D(std_y, j, i), SM_ELEMENT_D(std_y_exp, i, j));
            }
        }
        report("std_y", ds.max_abs, diff_rel(&ds), tol_delta);
    }

    SUNMatDestroy(cov_p);
    SUNMatDestroy(std_y);
    SUNMatDestroy(q_low_alt);
    SUNMatDestroy(q_up_alt);
    SUNMatDestroy(q_low);
    SUNMatDestroy(q_up);
    SUNMatDestroy(q_low_exp);
    SUNMatDestroy(q_up_exp);
    SUNMatDestroy(cov_p_exp);
    SUNMatDestroy(std_y_exp);
    SUNMatDestroy(media_tot);
    destroy_matrix_array(media_matrix);
    SUNMatDestroy(resid_loo);
    SUNMatDestroy(loo_params);
    N_VDestroy(theta_hat);
}

/* ---------------------------------------------------------------- main -- */

int main(int argc, char *argv[])
{
    if (argc < 4)
    {
        fprintf(stderr, "Usage: %s <baseline_dir> <cuqdyn_config.xml> <data_file>\n", argv[0]);
        return 2;
    }
    const char *dir = argv[1];
    const char *config_file = argv[2];
    const char *data_file = argv[3];

    char path[1024];
    snprintf(path, sizeof(path), "%s/layer2/theta_fixed.txt", dir);
    const int have3 = file_exists(path);
    snprintf(path, sizeof(path), "%s/layer3/theta_hat.txt", dir);
    const int have4 = file_exists(path);

    if (!have3 && !have4)
    {
        printf("No baseline exports found under %s.\n", dir);
        printf("Generate them with MATLAB first: gen_baseline('<model>').\n");
        return 77; /* ctest SKIP_RETURN_CODE */
    }

    if (init_cuqdyn_context_from_file(config_file) == NULL)
    {
        fprintf(stderr, "ERROR: cannot read cuqdyn config %s\n", config_file);
        return 2;
    }
    CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());

    CuqdynData data;
    if (read_data_file(data_file, &data) != 0)
    {
        fprintf(stderr, "ERROR: cannot read data file %s\n", data_file);
        return 2;
    }

    snprintf(path, sizeof(path), "%s/tol.txt", dir);
    const double tol_traj = read_kv_double(path, "layer2_traj", 1e-4);
    const double tol_sens = read_kv_double(path, "layer2_sens", 5e-3);
    const double tol_conf = read_kv_double(path, "layer3_conformal", 1e-9);
    const double tol_delta = read_kv_double(path, "layer3_delta", 1e-2);
    const double tol_covp = read_kv_double(path, "layer3_covp", tol_delta);

    printf("baseline dir : %s\n", dir);
    printf("config       : %s\n", config_file);
    printf("data         : %s\n\n", data_file);

    if (have3)
    {
        run_layer2(dir, &data, conf, tol_traj, tol_sens);
    }
    if (have4)
    {
        run_layer3(dir, &data, conf, tol_conf, tol_delta, tol_covp);
    }

    printf("\n%d checks, %d failed\n", g_checks, g_failures);
    destroy_cuqdyn_data(&data);
    return g_failures;
}
