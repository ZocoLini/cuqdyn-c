#include <assert.h>
#include <cuqdyn.h>
#include <math.h>
#include <stdio.h>

#include "config.h"

#ifndef EXAMPLES_DIR
#error "EXAMPLES_DIR must point at example-files/ (set by tests/CMakeLists.txt)"
#endif

/*
 * End-to-end runs over the shipped examples.
 *
 * Every scenario is a folder under example-files/ holding data.txt, one or more
 * cuqdyn-*.xml and a sacess-serial.xml, so adding a case here is a matter of
 * adding a row rather than another near-identical function. These are the same
 * files the README tells users to run, which is what keeps the examples honest.
 */
typedef struct
{
    const char *folder;
    const char *cuqdyn_config;
    const char *description;
    long n_states;
    int n_obs;
    /// Index of the first measured state, or -1 to leave it unchecked.
    int first_observed;
    /// The hybrid covariance also emits the plain FIM bands, so they can be compared.
    int expects_alt_bands;
} Scenario;

static const Scenario SCENARIOS[] = {
        // Fully observed: conformal bands cover every state and the run reduces
        // to the original CUQDyn1.
        {"logistic", "cuqdyn-fim.xml", "Logistic, single observed state", 1, 1, 0, 0},
        {"lotka-volterra", "cuqdyn-fim.xml", "Lotka-Volterra, fully observed", 2, 2, -1, 0},
        {"alpha-pinene", "cuqdyn-fim.xml", "Alpha-pinene, 5 observed states", 5, 5, -1, 0},
        // Partially observed: the hidden states go through the delta method.
        {"linear-cascade", "cuqdyn-fim.xml", "LinearCascade, 1 of 2 states observed", 2, 1, 1, 0},
        {"linear-cascade3", "cuqdyn-fim.xml", "LinearCascade3, 1 of 3 states observed", 3, 1, 2, 0},
        {"lv2-partobs", "cuqdyn-fim.xml", "Lotka-Volterra, predator hidden", 2, 1, 0, 0},
        {"sir", "cuqdyn-fim.xml", "SIR, 2 of 3 states hidden", 3, 1, 1, 0},
        // Same problem through the hybrid covariance, which also emits the plain
        // FIM bands so the two can be compared.
        {"sir", "cuqdyn-hybridcov.xml", "SIR, hybrid covariance", 3, 1, 1, 1},
        {"lv2-partobs", "cuqdyn-hybridcov.xml", "Lotka-Volterra hidden predator, hybrid covariance", 2, 1, 0, 1},
        // NF-kB is left out of the default run: 15 states and 29 parameters make
        // it far slower than the rest. example-files/nfkb/ carries its files.
};

static const int N_SCENARIOS = sizeof(SCENARIOS) / sizeof(SCENARIOS[0]);

static void run_scenario(const Scenario *scenario)
{
    char data_file[512];
    char cuqdyn_config_file[512];
    char sacess_config_file[512];

    snprintf(data_file, sizeof(data_file), EXAMPLES_DIR "/%s/data.txt", scenario->folder);
    snprintf(cuqdyn_config_file, sizeof(cuqdyn_config_file), EXAMPLES_DIR "/%s/%s", scenario->folder,
             scenario->cuqdyn_config);
    snprintf(sacess_config_file, sizeof(sacess_config_file), EXAMPLES_DIR "/%s/sacess-serial.xml", scenario->folder);

    // Written inside the build tree so a test run never dirties the examples.
    char *output_file = "cuqdyn_output";

    CuqDynContext context = init_cuqdyn_context_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    assert(cuqdyn_result->n_states == scenario->n_states);
    assert(cuqdyn_result->n_obs == scenario->n_obs);

    if (scenario->first_observed >= 0)
    {
        assert(cuqdyn_result->observed_idx[0] == scenario->first_observed);
    }

    // Produced for every run: the covariance describes the fit, not the
    // observability, so it exists even when every state is measured.
    assert(cuqdyn_result->cov_p != NULL);
    assert(cuqdyn_result->std_y != NULL);

    if (scenario->expects_alt_bands)
    {
        assert(cuqdyn_result->q_low_alt != NULL);
        assert(cuqdyn_result->q_up_alt != NULL);
    }
    else
    {
        assert(cuqdyn_result->q_low_alt == NULL);
        assert(cuqdyn_result->q_up_alt == NULL);
    }

    destroy_cuqdyn_result(cuqdyn_result);
    destroy_cuqdyn_context(context);
}

int main(void)
{
#if defined(MPI2) || defined(MPI)
    printf("No tests to execute with MPI\n");
    return 0;
#endif

    for (int i = 0; i < N_SCENARIOS; ++i)
    {
        run_scenario(&SCENARIOS[i]);
        printf("\tTest %d (%s) completed\n", i + 1, SCENARIOS[i].description);
    }

    return 0;
}
