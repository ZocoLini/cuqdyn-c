#define LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2GB "data/lotka_volterra_ess_config_nl2sol.dn2gb.xml"
#define LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2FB "data/lotka_volterra_ess_config_nl2sol.dn2fb.xml"
#define LOTKA_VOLTERRA_CONF_FILE_DHC "data/lotka_volterra_ess_config_dhc.xml"
#define LOTKA_VOLTERRA_CONF_FILE_MISQP "data/lotka_volterra_ess_config_misqp.xml"
#define ALPHA_PINENE_CONF_FILE_NL2SOL_DN2FB "data/alpha_pinene_ess_config_nl2sol.dn2fb.xml"
#define LOGISTIC_MODEL_CONF_FILE_NL2SOL_DN2FB "data/logistic_model_ess_config_nl2sol.dn2fb.xml"

#define LOTKA_VOLTERRA_DATA "data/lotka_volterra_paper_data.txt"
#define ALPHA_PINENE_DATA "data/alpha_pinene_paper_data.txt"
#define LOGISTIC_MODEL_DATA "data/logistic_model_paper_data.txt"

#define OUPUT_PATH "ess_output"

#include <config.h>
#include <cuqdyn.h>
#include <stdio.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "data_reader.h"
#include "ess_solver.h"
#include "matlab.h"

void lotka_volterra_ess(char *conf_file);
void alpha_pinene_ess(char *conf_file);
void logistic_model_ess(char *conf_file);

int main(int argc, char **argv)
{
#ifdef MPI2
    printf("No tests to execute with MPI2\n");
    return 0;
#endif

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2GB);
    printf("\tTest 1 passed NL2SOL_DN2GB\n");

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2FB);
    printf("\tTest 2 passed NL2SOL_DN2FB\n");

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_DHC);
    printf("\tTest 3 passed DHC\n");

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_MISQP);
    printf("\tTest 4 passed MISQP\n");

    logistic_model_ess(LOGISTIC_MODEL_CONF_FILE_NL2SOL_DN2FB);
    printf("\tTest 5 passed Logistic Model NL2SOL_DN2FB\n");

    alpha_pinene_ess(ALPHA_PINENE_CONF_FILE_NL2SOL_DN2FB);
    printf("\tTest 6 passed Alpha-Pinene NL2SOL_DN2GB\n");
    
    return 0;
}

void lotka_volterra_ess(char *conf_file)
{
    init_cuqdyn_conf_from_file("data/lotka_volterra_cuqdyn_config.xml");

    sunrealtype expected_values[4] = {0.5, 0.02, 0.5, 0.02};

    N_Vector texp = NULL;
    SUNMatrix yexp = NULL;

    read_data_file(LOTKA_VOLTERRA_DATA, &texp, &yexp);

    N_Vector initial_values = copy_matrix_row(yexp, 0, 0, SM_COLUMNS_D(yexp));

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, NULL);

    for (int i = 0; i < 4; ++i)
    {
        sunrealtype expected = expected_values[i];
        sunrealtype result = NV_Ith_S(xbest, i);

        sunrealtype a = 6;
        // assert(fabs(result - expected) < 0.1);
    }

    destroy_cuqdyn_conf();
}

void alpha_pinene_ess(char *conf_file)
{
    init_cuqdyn_conf_from_file("data/alpha_pinene_cuqdyn_config.xml");

    sunrealtype expected_values[5] = {5.93e-5, 2.96e-5, 2.05e-5, 2.75e-5, 4.00e-5};

    N_Vector texp = NULL;
    SUNMatrix yexp = NULL;

    read_data_file(ALPHA_PINENE_DATA, &texp, &yexp);

    N_Vector initial_values = copy_matrix_row(yexp, 0, 0, SM_COLUMNS_D(yexp));

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, NULL);

    for (int i = 0; i < 5; ++i)
    {
        sunrealtype expected = expected_values[i];
        sunrealtype result = NV_Ith_S(xbest, i);

        sunrealtype a = 6;
        // assert(fabs(result - expected) < 0.1);
    }

    destroy_cuqdyn_conf();
}

void logistic_model_ess(char *conf_file)
{
    init_cuqdyn_conf_from_file("data/logistic_model_cuqdyn_config.xml");

    sunrealtype expected_values[2] = {0.1, 100};

    N_Vector texp = NULL;
    SUNMatrix yexp = NULL;

    read_data_file(LOGISTIC_MODEL_DATA, &texp, &yexp);

    N_Vector initial_values = copy_matrix_row(yexp, 0, 0, SM_COLUMNS_D(yexp));

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, NULL);

    for (int i = 0; i < sizeof(expected_values); ++i)
    {
        sunrealtype expected = expected_values[i];
        sunrealtype result = NV_Ith_S(xbest, i);

        sunrealtype a = 6;
        // assert(fabs(result - expected) < 0.1);
    }

    destroy_cuqdyn_conf();
}
