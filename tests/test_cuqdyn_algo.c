#include <assert.h>
#include <cuqdyn.h>
#include <math.h>
#include <stdio.h>

#include "config.h"

void test_lotka_volterra();
void test_linear_cascade();
void test_lotka_volterra_partobs();
void test_sir_hybridcov();
void test_nfkb();

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
