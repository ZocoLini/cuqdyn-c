#include <assert.h>
#include <config.h>
#include <cuqdyn.h>
#include <math.h>
#include <stdio.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "data_reader.h"
#include "ess_solver.h"
#include "example_files.h"
#include "matlab.h"
#include "nvector/nvector_serial.h"

#define OUTPUT_PATH "ess_output"
#define MAX_PARAMETERS 8

#define PARAMETER_TOLERANCE 1

typedef struct
{
    const char *model;
    const char *description;

    sunrealtype expected[MAX_PARAMETERS];

    int n_parameters;
} Scenario;

static const Scenario SCENARIOS[] = {
        {"lotka-volterra", "Lotka-Volterra", {0.5, 0.02, 0.5, 0.02}, 4},
        {"logistic", "Logistic Model", {0.1, 102}, 2},
        {"alpha-pinene", "Alpha-Pinene", {5.93e-5, 2.96e-5, 2.05e-5, 2.75e-5, 4.00e-5}, 5},
};

static const int N_SCENARIOS = sizeof(SCENARIOS) / sizeof(SCENARIOS[0]);

static void run_scenario(const Scenario *scenario)
{
    CuqDynContext context = init_cuqdyn_context_from_file(example_conf(scenario->model));

    CuqdynData data;
    assert(read_data_file(example_data(scenario->model), &data) == 0);

    N_Vector texp = data.times;
    SUNMatrix yexp = data.observed_data;
    N_Vector initial_values = copy_matrix_column(yexp, 0, 0, SM_ROWS_D(yexp));

    N_Vector xbest = execute_ess_solver(example_sacess_conf(scenario->model), OUTPUT_PATH, texp, yexp, initial_values,
                                        NULL, data.observed_idx);

    for (int i = 0; i < scenario->n_parameters; ++i)
    {
        assert(fabs(NV_Ith_S(xbest, i) - scenario->expected[i]) < PARAMETER_TOLERANCE);
    }

    destroy_cuqdyn_context(context);
}

int main(void)
{
#if defined(MPI2) || defined(MPI)
    printf("No tests to execute with MPI2\n");
    return 0;
#endif

    for (int i = 0; i < N_SCENARIOS; ++i)
    {
        run_scenario(&SCENARIOS[i]);
        printf("\tTest %d passed %s\n", i + 1, SCENARIOS[i].description);
    }

    return 0;
}
