// Every shipped example drives eSS with the same local solver, so one run per
// model is the whole of the coverage: there are no solver variants left to sweep.
#define LOTKA_VOLTERRA_CONF EXAMPLES_DIR "/lotka-volterra/sacess-serial.xml"
#define ALPHA_PINENE_CONF EXAMPLES_DIR "/alpha-pinene/sacess-serial.xml"
#define LOGISTIC_MODEL_CONF EXAMPLES_DIR "/logistic/sacess-serial.xml"

#define LOTKA_VOLTERRA_DATA EXAMPLES_DIR "/lotka-volterra/data.txt"
#define ALPHA_PINENE_DATA EXAMPLES_DIR "/alpha-pinene/data.txt"
#define LOGISTIC_MODEL_DATA EXAMPLES_DIR "/logistic/data.txt"

#define OUPUT_PATH "ess_output"

#include <assert.h>
#include <config.h>
#include <cuqdyn.h>
#include <math.h>
#include <stdio.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "data_reader.h"
#include "ess_solver.h"
#include "matlab.h"
#include "nvector/nvector_serial.h"

void lotka_volterra_ess(char *conf_file);
void alpha_pinene_ess(char *conf_file);
void logistic_model_ess(char *conf_file);

int main(int argc, char **argv)
{
#if defined(MPI2) || defined(MPI)
    printf("No tests to execute with MPI2\n");
    return 0;
#endif

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF);
    printf("\tTest 1 passed Lotka-Volterra\n");

    logistic_model_ess(LOGISTIC_MODEL_CONF);
    printf("\tTest 2 passed Logistic Model\n");

    alpha_pinene_ess(ALPHA_PINENE_CONF);
    printf("\tTest 3 passed Alpha-Pinene\n");

    return 0;
}

void lotka_volterra_ess(char *conf_file)
{
    CuqDynContext context = init_cuqdyn_context_from_file(EXAMPLES_DIR "/lotka-volterra/cuqdyn-fim.xml");

    sunrealtype expected_values[4] = {0.5, 0.02, 0.5, 0.02};

    CuqdynData data;
    assert(read_data_file(LOTKA_VOLTERRA_DATA, &data) == 0);

    N_Vector texp = data.times;
    SUNMatrix yexp = data.observed_data;
    N_Vector initial_values = copy_matrix_column(yexp, 0, 0, SM_ROWS_D(yexp));

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, NULL, data.observed_idx);

    for (int i = 0; i < 4; ++i)
    {
        sunrealtype expected = expected_values[i];
        sunrealtype result = NV_Ith_S(xbest, i);

        assert(fabs(result - expected) < 1);
    }

    destroy_cuqdyn_context(context);
}

void alpha_pinene_ess(char *conf_file)
{
    CuqDynContext context = init_cuqdyn_context_from_file(EXAMPLES_DIR "/alpha-pinene/cuqdyn-fim.xml");

    sunrealtype expected_values[5] = {5.93e-5, 2.96e-5, 2.05e-5, 2.75e-5, 4.00e-5};

    CuqdynData data;
    assert(read_data_file(ALPHA_PINENE_DATA, &data) == 0);

    N_Vector texp = data.times;
    SUNMatrix yexp = data.observed_data;
    N_Vector initial_values = copy_matrix_column(yexp, 0, 0, SM_ROWS_D(yexp));

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, NULL, data.observed_idx);

    for (int i = 0; i < 5; ++i)
    {
        sunrealtype expected = expected_values[i];
        sunrealtype result = NV_Ith_S(xbest, i);

        assert(fabs(result - expected) < 1);
    }

    destroy_cuqdyn_context(context);
}

void logistic_model_ess(char *conf_file)
{
    CuqDynContext context = init_cuqdyn_context_from_file(EXAMPLES_DIR "/logistic/cuqdyn-fim.xml");

    sunrealtype expected_values[2] = {0.1, 102};

    CuqdynData data;
    assert(read_data_file(LOGISTIC_MODEL_DATA, &data) == 0);

    N_Vector texp = data.times;
    SUNMatrix yexp = data.observed_data;
    N_Vector initial_values = copy_matrix_column(yexp, 0, 0, SM_ROWS_D(yexp));

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, NULL, data.observed_idx);

    for (int i = 0; i < 2; ++i)
    {
        sunrealtype expected = expected_values[i];
        sunrealtype result = NV_Ith_S(xbest, i);

        assert(fabs(result - expected) < 1);
    }

    destroy_cuqdyn_context(context);
}
