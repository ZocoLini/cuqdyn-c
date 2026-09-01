#include <assert.h>
#include <cuqdyn.h>
#include <math.h>
#include <stdio.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "example_files.h"

/*
 * End-to-end runs over the shipped examples.
 *
 * Every scenario is a folder under example-files/ holding data.txt, cuqdyn.xml
 * and a sacess-serial.xml, so adding a case here is a matter of adding a row
 * rather than another near-identical function. These are the same files the
 * README tells users to run, which is what keeps the examples honest.
 */
typedef struct
{
    const char *model;
    const char *description;
    long n_states;
    int n_obs;
    /// Index of the first measured state, or -1 to leave it unchecked.
    int first_observed;
} Scenario;

static const Scenario SCENARIOS[] = {
        // Fully observed: conformal bands cover every state and the run reduces
        // to the original CUQDyn1.
        {"logistic", "Logistic, single observed state", 1, 1, 0},
        {"lotka-volterra", "Lotka-Volterra, fully observed", 2, 2, -1},
        {"alpha-pinene", "Alpha-pinene, 5 observed states", 5, 5, -1},
        // Partially observed: the hidden states go through the delta method, and
        // are the only ones where the two covariance varieties differ.
        {"linear-cascade", "LinearCascade, 1 of 2 states observed", 2, 1, 1},
        {"linear-cascade3", "LinearCascade3, 1 of 3 states observed", 3, 1, 2},
        {"lv2-partobs", "Lotka-Volterra, predator hidden", 2, 1, 0},
        {"sir", "SIR, 2 of 3 states hidden", 3, 1, 1},
        // NF-kB is left out of the default run: 15 states and 29 parameters make
        // it far slower than the rest. example-files/nfkb/ carries its files.
};

static const int N_SCENARIOS = sizeof(SCENARIOS) / sizeof(SCENARIOS[0]);

static void run_scenario(const Scenario *scenario)
{
    const char *cuqdyn_config_file = example_conf(scenario->model);
    const char *sacess_config_file = example_sacess_conf(scenario->model);
    const char *data_file = example_data(scenario->model);

    // Written inside the build tree so a test run never dirties the examples.
    const char *output_file = "cuqdyn_output";

    CuqDynContext context = init_cuqdyn_context_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    assert(cuqdyn_result->n_states == scenario->n_states);
    assert(cuqdyn_result->n_obs == scenario->n_obs);

    if (scenario->first_observed >= 0)
    {
        assert(cuqdyn_result->observed_idx[0] == scenario->first_observed);
    }

    // Both varieties on every run, with nothing to select. The covariance
    // describes the fit rather than the observability, so it exists even when
    // every state is measured.
    const UqBands *varieties[] = {&cuqdyn_result->fim, &cuqdyn_result->hybrid};

    for (int v = 0; v < 2; ++v)
    {
        assert(varieties[v]->q_low != NULL);
        assert(varieties[v]->q_up != NULL);
        assert(varieties[v]->cov_p != NULL);
        assert(varieties[v]->std_y != NULL);
    }

    // The covariance only reaches the states the data never measures, so the two
    // agree exactly on the measured ones and the initial condition.
    for (int j = 0; j < scenario->n_obs; ++j)
    {
        const long state = cuqdyn_result->observed_idx[j];

        for (long i = 0; i < SM_ROWS_D(cuqdyn_result->fim.q_low); ++i)
        {
            assert(SM_ELEMENT_D(cuqdyn_result->fim.q_low, i, state) ==
                   SM_ELEMENT_D(cuqdyn_result->hybrid.q_low, i, state));
            assert(SM_ELEMENT_D(cuqdyn_result->fim.q_up, i, state) ==
                   SM_ELEMENT_D(cuqdyn_result->hybrid.q_up, i, state));
        }
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
