#include <assert.h>
#include <config.h>
#include <cuqdyn.h>
#include <math.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <sunmatrix/sunmatrix_dense.h>
#include <time.h>

#include "example_files.h"
#include "ode_solver.h"

#define MAX_TIMES 16
#define MAX_PARAMETERS 8
#define MAX_STATES 8
#define MAX_CHECKS 8

typedef struct
{
    long state;
    long time;
    sunrealtype expected;
    sunrealtype tolerance;
} StateCheck;

typedef struct
{
    const char *model;
    const char *description;

    sunrealtype parameters[MAX_PARAMETERS];
    sunrealtype initial_values[MAX_STATES];
    sunrealtype times[MAX_TIMES];
    StateCheck checks[MAX_CHECKS];

    int n_times;
    int n_parameters;
    int n_states;
    int n_checks;
} Scenario;

static const Scenario SCENARIOS[] = {
        {
                .model = "lotka-volterra",
                .description = "Lotka-Volterra a = g = 0.5, b = d = 0.02 and y(0) = (10, 5)",
                .n_times = 9,
                .times = {1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0},
                .n_parameters = 4,
                .parameters = {0.5, 0.02, 0.5, 0.02},
                .n_states = 2,
                .initial_values = {10, 5},
                .n_checks = 4,
                .checks =
                        {
                                {0, 0, 15.10, 0.01},
                                {1, 0, 3.883, 0.001},
                                {0, 6, 53.79, 0.01},
                                {1, 6, 5.456, 0.001},
                        },
        },
        {
                .model = "alpha-pinene",
                .description = "Alpha-pinene",
                .n_times = 9,
                .times = {0, 1230, 3060, 4920, 7800, 10680, 15030, 22620, 36420},
                .n_parameters = 5,
                .parameters = {5.93e-5, 2.96e-5, 2.05e-5, 2.75e-5, 4.00e-5},
                .n_states = 5,
                .initial_values = {100, 0, 0, 0, 0},
                .n_checks = 4,
                .checks =
                        {
                                {0, 0, 100, 0.01},
                                {2, 0, 0, 0.001},
                                {0, 6, 2.510e+01, 2},
                                {1, 6, 4.814e+01, 2},
                        },
        },
        {
                .model = "logistic",
                .description = "Logistic model",
                .n_times = 11,
                .times = {0, 10, 20, 20, 40, 50, 60, 70, 80, 90, 100},
                .n_parameters = 2,
                .parameters = {0.1, 100},
                .n_states = 1,
                .initial_values = {10},
                .n_checks = 3,
                .checks =
                        {
                                {0, 0, 10, 0.01},
                                {0, 5, 9.428e+01, 0.01},
                                {0, 6, 9.782e+01, 0.01},
                        },
        },
};

static const int N_SCENARIOS = sizeof(SCENARIOS) / sizeof(SCENARIOS[0]);

static N_Vector to_vector(const sunrealtype *values, const int len)
{
    N_Vector vector = New_Serial(len);

    for (int i = 0; i < len; ++i)
    {
        NV_Ith_S(vector, i) = values[i];
    }

    return vector;
}

static void run_scenario(const Scenario *scenario)
{
    CuqDynContext context = init_cuqdyn_context_from_file(example_conf(scenario->model));

    N_Vector times = to_vector(scenario->times, scenario->n_times);
    N_Vector parameters = to_vector(scenario->parameters, scenario->n_parameters);
    N_Vector initial_values = to_vector(scenario->initial_values, scenario->n_states);

    const sunrealtype t0 = 0.0;

    TransposedStates result = solve_ode(parameters, initial_values, t0, times, NULL);

    assert(result != NULL);
    assert(SM_COLUMNS_D(result) == scenario->n_times);
    assert(SM_ROWS_D(result) == scenario->n_states);

    for (int i = 0; i < scenario->n_checks; ++i)
    {
        const StateCheck check = scenario->checks[i];

        assert(fabs(SM_ELEMENT_D(result, check.state, check.time) - check.expected) < check.tolerance);
    }

    destroy_cuqdyn_context(context);
    SUNMatDestroy(result);
    N_VDestroy(times);
    N_VDestroy(parameters);
    N_VDestroy(initial_values);
}

int main(void)
{
    for (int i = 0; i < N_SCENARIOS; ++i)
    {
        run_scenario(&SCENARIOS[i]);
        printf("\tTest %d (%s) passed\n", i + 1, SCENARIOS[i].description);
    }

    return 0;
}
