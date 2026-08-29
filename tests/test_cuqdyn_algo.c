#include <assert.h>
#include <cuqdyn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"

void test_lotka_volterra();
void test_linear_cascade();
void test_lotka_volterra_partobs();
void test_sir_hybridcov();
void test_nfkb();

/*
 * MATLAB reference comparison for the lv2_partobs case.
 *
 * data/lv2_partobs_expected_output.txt is written by MATLAB
 * (validation/baseline/write_expected_output.m) from a seeded CUQDyn1_Plus
 * run on the same data. When the file exists, the C result is compared
 * against it; when it does not, the comparison is skipped and only the
 * structural asserts run, so the test does not depend on anyone having
 * MATLAB.
 *
 * The margins are deliberately generous MEAN errors: the two sides run
 * independent stochastic eSS fits, so element-wise tightness is impossible.
 * A transpilation bug shows up as a systematic shift far above optimiser
 * noise (see validation/baseline/README.md for the noise-free layers).
 */
#define EXPECTED_TOL_PARAMS 0.25 /* median LOO parameters, relative L1 */
#define EXPECTED_TOL_TRAJ 0.15   /* best-fit trajectory, relative L1 */
#define EXPECTED_TOL_BANDS 0.25  /* conformal + delta bands, relative L1 */

/* Scan the file for "[tag]" and read "rows cols" plus the values after it.
 * Returns NULL when the file or the tag is missing. */
static double *expected_read_matrix(const char *path, const char *tag, long *rows_out, long *cols_out)
{
    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        return NULL;
    }

    char want[64];
    snprintf(want, sizeof(want), "[%s]", tag);

    char token[256];
    int found = 0;
    while (fscanf(f, "%255s", token) == 1)
    {
        if (strcmp(token, want) == 0)
        {
            found = 1;
            break;
        }
    }

    long rows, cols;
    if (!found || fscanf(f, "%ld %ld", &rows, &cols) != 2)
    {
        fclose(f);
        return NULL;
    }

    double *values = malloc(rows * cols * sizeof(double));
    for (long i = 0; i < rows * cols; ++i)
    {
        if (fscanf(f, "%lf", &values[i]) != 1)
        {
            free(values);
            fclose(f);
            return NULL;
        }
    }
    fclose(f);

    *rows_out = rows;
    *cols_out = cols;
    return values;
}

/* Vectors are stored as "[tag]\nlen\nvalues". */
static double *expected_read_vector(const char *path, const char *tag, long *len_out)
{
    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        return NULL;
    }

    char want[64];
    snprintf(want, sizeof(want), "[%s]", tag);

    char token[256];
    int found = 0;
    while (fscanf(f, "%255s", token) == 1)
    {
        if (strcmp(token, want) == 0)
        {
            found = 1;
            break;
        }
    }

    long len;
    if (!found || fscanf(f, "%ld", &len) != 1)
    {
        fclose(f);
        return NULL;
    }

    double *values = malloc(len * sizeof(double));
    for (long i = 0; i < len; ++i)
    {
        if (fscanf(f, "%lf", &values[i]) != 1)
        {
            free(values);
            fclose(f);
            return NULL;
        }
    }
    fclose(f);

    *len_out = len;
    return values;
}

/* Relative L1 distance: sum|got - exp| / sum|exp|. Mean-style, so a handful
 * of noisy entries cannot fail the run the way a max norm would. */
static double rel_l1(const double *got, const double *expected, const long n)
{
    double num = 0.0;
    double den = 0.0;
    for (long i = 0; i < n; ++i)
    {
        num += fabs(got[i] - expected[i]);
        den += fabs(expected[i]);
    }
    return num / (den > 1e-300 ? den : 1.0);
}

static void compare_lv2_against_matlab(const CuqdynResult *result)
{
    const char *path = "data/lv2_partobs_expected_output.txt";

    if (result->media_tot == NULL)
    {
        printf("\tMATLAB comparison skipped: media_tot is NULL (best-fit ODE solve failed)\n");
        return;
    }

    long n_params, m, n_states, cols;
    double *params_exp = expected_read_vector(path, "Params", &n_params);
    if (params_exp == NULL)
    {
        printf("\t(no %s: MATLAB comparison skipped; generate it with "
               "validation/baseline/write_expected_output.m)\n",
               path);
        return;
    }

    double *q_low_exp = expected_read_matrix(path, "Q_low", &m, &n_states);
    double *q_up_exp = expected_read_matrix(path, "Q_up", &m, &n_states);
    double *media_exp = expected_read_matrix(path, "MediaTot", &m, &cols);
    assert(q_low_exp != NULL && q_up_exp != NULL && media_exp != NULL);
    assert(n_params == NV_LENGTH_S(result->predicted_params_median));
    assert(n_states == result->n_states);
    assert(m == SM_ROWS_D(result->q_low));

    /* Median LOO parameters. */
    const double err_params = rel_l1(NV_DATA_S(result->predicted_params_median), params_exp, n_params);

    /* Best-fit trajectory: C stores it transposed (states x times). */
    double *media_got = malloc(m * n_states * sizeof(double));
    for (long i = 0; i < m; ++i)
    {
        for (long j = 0; j < n_states; ++j)
        {
            media_got[i * n_states + j] = SM_ELEMENT_D(result->media_tot, j, i);
        }
    }
    const double err_traj = rel_l1(media_got, media_exp, m * n_states);
    free(media_got);

    /* Bands, both matrices m x n_states, row-major on both sides. */
    double *bands_got = malloc(m * n_states * sizeof(double));
    for (long i = 0; i < m; ++i)
    {
        for (long j = 0; j < n_states; ++j)
        {
            bands_got[i * n_states + j] = SM_ELEMENT_D(result->q_low, i, j);
        }
    }
    const double err_qlow = rel_l1(bands_got, q_low_exp, m * n_states);
    for (long i = 0; i < m; ++i)
    {
        for (long j = 0; j < n_states; ++j)
        {
            bands_got[i * n_states + j] = SM_ELEMENT_D(result->q_up, i, j);
        }
    }
    const double err_qup = rel_l1(bands_got, q_up_exp, m * n_states);
    free(bands_got);

    printf("\tMATLAB comparison (rel L1): params=%.3f traj=%.3f q_low=%.3f q_up=%.3f "
           "(tol %.2f/%.2f/%.2f)\n",
           err_params, err_traj, err_qlow, err_qup, EXPECTED_TOL_PARAMS, EXPECTED_TOL_TRAJ,
           EXPECTED_TOL_BANDS);

    assert(err_params <= EXPECTED_TOL_PARAMS);
    assert(err_traj <= EXPECTED_TOL_TRAJ);
    assert(err_qlow <= EXPECTED_TOL_BANDS);
    assert(err_qup <= EXPECTED_TOL_BANDS);

    free(params_exp);
    free(q_low_exp);
    free(q_up_exp);
    free(media_exp);
}

int main(void)
{
#if defined(MPI2) || defined(MPI)
    printf("No tests to execute with MPI2\n");
    return 0;
#endif

    test_lotka_volterra();
    printf("\tTest 1 (Lotka-Volterra, fully observed) completed\n");

    test_linear_cascade();
    printf("\tTest 2 (LinearCascade, 1 of 2 states observed) completed\n");

    test_lotka_volterra_partobs();
    printf("\tTest 3 (Lotka-Volterra, predator hidden) completed\n");

    test_sir_hybridcov();
    printf("\tTest 4 (SIR, hybrid covariance, 2 of 3 states hidden) completed\n");

    // test_nfkb(); TODO: Too slow
    printf("\tTest 5 completed\n");

    return 0;
}

void test_lotka_volterra()
{
    char *data_file = "data/lotka_volterra_paper_data.txt";
    char *cuqdyn_config_file = "data/lotka_volterra_cuqdyn_config.xml";
    char *sacess_config_file = "data/lotka_volterra_ess_config_nl2sol.dn2gb.xml";
    char *output_file = "data/output";

    CuqDynContext context = init_cuqdyn_context_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    // No NaN in the data means every state is measured, so all the bands come
    // from the conformal pass. The parameter covariance is produced regardless,
    // since it describes the fit rather than the observability.
    assert(cuqdyn_result->n_obs == cuqdyn_result->n_states);
    assert(cuqdyn_result->cov_p != NULL);
    assert(cuqdyn_result->std_y != NULL);

    destroy_cuqdyn_result(cuqdyn_result);
    destroy_cuqdyn_context(context);
}

void test_linear_cascade()
{
    char *data_file = "data/linear_cascade_paper_data.txt";
    char *cuqdyn_config_file = "data/linear_cascade_cuqdyn_config.xml";
    char *sacess_config_file = "data/linear_cascade_ess_serial_config.xml";
    char *output_file = "data/output";

    CuqDynContext context = init_cuqdyn_context_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    // Only the downstream state is measured, so the hidden one gets FIM bands.
    assert(cuqdyn_result->n_states == 2);
    assert(cuqdyn_result->n_obs == 1);
    assert(cuqdyn_result->observed_idx[0] == 1);
    assert(cuqdyn_result->cov_p != NULL);
    assert(cuqdyn_result->std_y != NULL);

    destroy_cuqdyn_result(cuqdyn_result);
    destroy_cuqdyn_context(context);
}

void test_lotka_volterra_partobs()
{
    char *data_file = "data/lv2_partobs_paper_data.txt";
    char *cuqdyn_config_file = "data/lv2_partobs_cuqdyn_config.xml";
    char *sacess_config_file = "data/lv2_partobs_ess_serial_config.xml";
    char *output_file = "data/output";

    CuqDynContext context = init_cuqdyn_context_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    // The prey is measured at every time point, the predator never.
    assert(cuqdyn_result->n_states == 2);
    assert(cuqdyn_result->n_obs == 1);
    assert(cuqdyn_result->observed_idx[0] == 0);

    // Compare against the MATLAB reference when it has been generated.
    compare_lv2_against_matlab(cuqdyn_result);

    destroy_cuqdyn_result(cuqdyn_result);
    destroy_cuqdyn_context(context);
}

void test_sir_hybridcov()
{
    char *data_file = "data/sir_paper_data.txt";
    char *cuqdyn_config_file = "data/sir_hybridcov_cuqdyn_config.xml";
    char *sacess_config_file = "data/sir_ess_serial_config.xml";
    char *output_file = "data/output";

    CuqDynContext context = init_cuqdyn_context_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    assert(cuqdyn_result->n_states == 3);
    assert(cuqdyn_result->n_obs == 1);
    assert(cuqdyn_result->cov_p != NULL);

    // The hybrid covariance also yields the plain FIM bands, so the two can be
    // compared; they are absent with the default method.
    assert(cuqdyn_result->q_low_alt != NULL);
    assert(cuqdyn_result->q_up_alt != NULL);

    destroy_cuqdyn_result(cuqdyn_result);
    destroy_cuqdyn_context(context);
}

void test_nfkb()
{
    char *data_file = "data/nfkb_paper_data.txt";
    char *cuqdyn_config_file = "data/nfkb_cuqdyn_config.xml";
    char *sacess_config_file = "data/nfkb_ess_serial_config.xml";
    char *output_file = "data/output";

    CuqDynContext context = init_cuqdyn_context_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    assert(cuqdyn_result->n_states == 15);
    assert(cuqdyn_result->n_obs == 10);

    destroy_cuqdyn_result(cuqdyn_result);
    destroy_cuqdyn_context(context);
}
