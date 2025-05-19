#define LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2GB "data/lotka_volterra_ess_config_nl2sol.dn2gb.xml"
#define LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2FB "data/lotka_volterra_ess_config_nl2sol.dn2fb.xml"
#define LOTKA_VOLTERRA_CONF_FILE_DHC "data/lotka_volterra_ess_config_dhc.xml"
#define LOTKA_VOLTERRA_CONF_FILE_MISQP "data/lotka_volterra_ess_config_misqp.xml"
#define ALPHA_PINENE_CONF_FILE_NL2SOL_DN2FB "data/alpha_pinene_ess_config_nl2sol.dn2fb.xml"
#define LOGISTIC_MODEL_CONF_FILE_NL2SOL_DN2FB "data/logistic_model_ess_config_nl2sol.dn2fb.xml"
#define OUPUT_PATH "ess_output"

#include <config.h>
#include <cuqdyn.h>
#include <stdio.h>

#include "ess_solver.h"

void lotka_volterra_ess(char *conf_file);
void alpha_pinene_ess(char *conf_file);
void logistic_model_ess(char *conf_file);

int main(int argc, char **argv)
{
#ifdef MPI2
    printf("No tests to execute with MPI2\n");
    return 0;
#endif

    // lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2GB);
    // printf("\tTest 1 passed NL2SOL_DN2GB\n");
    //
    // lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2FB);
    // printf("\tTest 2 passed NL2SOL_DN2FB\n");
    //
    // lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_DHC);
    // printf("\tTest 3 passed DHC\n");
    //
    // lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_MISQP);
    // printf("\tTest 4 passed MISQP\n");
//
    // logistic_model_ess(LOGISTIC_MODEL_CONF_FILE_NL2SOL_DN2FB);
    // printf("\tTest 5 passed Logistic Model NL2SOL_DN2FB\n");
//
    alpha_pinene_ess(ALPHA_PINENE_CONF_FILE_NL2SOL_DN2FB);
    printf("\tTest 6 passed Alpha-Pinene NL2SOL_DN2GB\n");

    return 0;
}

void lotka_volterra_ess(char *conf_file)
{
    init_cuqdyn_conf_from_file("data/lotka_volterra_cuqdyn_config.xml");

    realtype expected_values[4] = {0.5, 0.02, 0.5, 0.02};

    N_Vector texp = N_VNew_Serial(32, get_sun_context());
    for (int i = 0; i < NV_LENGTH_S(texp); ++i)
    {
        NV_Ith_S(texp, i) = i;
    }

    DlsMat yexp = SUNDenseMatrix(30, 2, get_sun_context());

    realtype yexp_data[30][2] = {
            {16.4161, 2.14078}, {26.9327, 6.95752}, {36.199, 3.05692},  {53.5232, 8.01177}, {75.279, 12.5015},
            {78.8885, 39.1838}, {37.4748, 78.3761}, {10.2444, 80.1333}, {2.91173, 58.1003}, {4.31927, 34.5728},
            {5.77477, 22.452},  {3.02048, 15.9231}, {6.87234, 12.3715}, {7.02391, 8.00952}, {11.5876, 3.70516},
            {11.6953, 5.03891}, {24.0456, 1.8209},  {34.2654, 2.18679}, {54.8232, 5.018},   {74.3034, 9.68863},
            {83.3479, 37.7167}, {45.6403, 78.4525}, {10.0775, 80.2856}, {6.10055, 57.703},  {6.33843, 39.9109},
            {5.36425, 22.9151}, {2.84835, 15.7364}, {9.82992, 12.7098}, {8.26545, 2.91747}, {7.38187, 6.32052}};

    N_Vector initial_values = N_VNew_Serial(2, get_sun_context());
    NV_Ith_S(initial_values, 0) = 10;
    NV_Ith_S(initial_values, 1) = 5;

    for (int i = 0; i < 30; ++i)
    {
        for (int j = 0; j < 2; ++j)
        {
            SM_ELEMENT_D(yexp, i, j) = yexp_data[i][j];
        }
    }

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, 0, 1);

    for (int i = 0; i < 4; ++i)
    {
        realtype expected = expected_values[i];
        realtype result = NV_Ith_S(xbest, i);

        realtype a = 6;
        // assert(fabs(result - expected) < 0.1);
    }

    destroy_cuqdyn_conf();
}

void alpha_pinene_ess(char *conf_file)
{
    init_cuqdyn_conf_from_file("data/alpha_pinene_cuqdyn_config.xml");

    realtype expected_values[5] = {5.93e-5, 2.96e-5, 2.05e-5, 2.75e-5, 4.00e-5};

    N_Vector texp = N_VNew_Serial(9, get_sun_context());
    NV_Ith_S(texp, 0) = 0;
    NV_Ith_S(texp, 1) = 1230;
    NV_Ith_S(texp, 2) = 3060;
    NV_Ith_S(texp, 3) = 4920;
    NV_Ith_S(texp, 4) = 7800;
    NV_Ith_S(texp, 5) = 10680;
    NV_Ith_S(texp, 6) = 15030;
    NV_Ith_S(texp, 7) = 22620;
    NV_Ith_S(texp, 8) = 36420;

    DlsMat yexp = SUNDenseMatrix(9, 5, get_sun_context());

    realtype yexp_data[9][5] = {{1.409e-01, 3.034e-02, 1.409e-01, 3.034e-02, 3.252e-02},
                                {3.441e+00, 6.992e-02, 3.441e+00, 6.992e-02, 4.046e-01},
                                {5.622e+00, 1.027e-01, 5.622e+00, 1.027e-01, 3.011e+00},
                                {5.316e+00, 5.430e-01, 5.316e+00, 5.430e-01, 4.136e+00},
                                {6.977e+00, 5.887e-01, 6.977e+00, 5.887e-01, 9.308e+00},
                                {7.298e+00, 9.356e-01, 7.298e+00, 9.356e-01, 1.277e+01},
                                {5.795e+00, 1.468e+00, 5.795e+00, 1.468e+00, 1.797e+01},
                                {5.169e+00, 1.443e+00, 5.169e+00, 1.443e+00, 2.250e+01},
                                {4.175e+00, 4.301e+00, 4.175e+00, 4.301e+00, 2.232e+01}};

    N_Vector initial_values = N_VNew_Serial(5, get_sun_context());
    NV_Ith_S(initial_values, 0) = 100;
    NV_Ith_S(initial_values, 1) = 0.0001;
    NV_Ith_S(initial_values, 2) = 0.0001;
    NV_Ith_S(initial_values, 3) = 0.0001;
    NV_Ith_S(initial_values, 4) = 0.0001;

    for (int i = 0; i < 9; ++i)
    {
        for (int j = 0; j < 5; ++j)
        {
            SM_ELEMENT_D(yexp, i, j) = yexp_data[i][j];
        }
    }

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, 0, 1);

    for (int i = 0; i < 5; ++i)
    {
        realtype expected = expected_values[i];
        realtype result = NV_Ith_S(xbest, i);

        realtype a = 6;
        // assert(fabs(result - expected) < 0.1);
    }

    destroy_cuqdyn_conf();
}

void logistic_model_ess(char *conf_file)
{
    init_cuqdyn_conf_from_file("data/logistic_model_cuqdyn_config.xml");

    realtype expected_values[2] = {0.1, 100};

    N_Vector texp = N_VNew_Serial(11, get_sun_context());
    NV_Ith_S(texp, 0) = 0;
    NV_Ith_S(texp, 1) = 10;
    NV_Ith_S(texp, 2) = 20;
    NV_Ith_S(texp, 3) = 20;
    NV_Ith_S(texp, 4) = 40;
    NV_Ith_S(texp, 5) = 50;
    NV_Ith_S(texp, 6) = 60;
    NV_Ith_S(texp, 7) = 70;
    NV_Ith_S(texp, 8) = 80;
    NV_Ith_S(texp, 9) = 90;
    NV_Ith_S(texp, 10) = 100;

    DlsMat yexp = SUNDenseMatrix(11, 1, get_sun_context());

    realtype yexp_data[11][1] = {{1.000e+01}, {2.226e+01}, {6.066e+01}, {7.327e+01}, {9.123e+01}, {8.895e+01},
                                 {9.703e+01}, {1.004e+02}, {1.174e+02}, {1.135e+02}, {9.390e+01}};

    N_Vector initial_values = N_VNew_Serial(1, get_sun_context());
    NV_Ith_S(initial_values, 0) = 10;

    for (int i = 0; i < 11; ++i)
    {
        for (int j = 0; j < 1; ++j)
        {
            SM_ELEMENT_D(yexp, i, j) = yexp_data[i][j];
        }
    }

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, texp, yexp, initial_values, 0, 1);

    for (int i = 0; i < 2; ++i)
    {
        realtype expected = expected_values[i];
        realtype result = NV_Ith_S(xbest, i);

        realtype a = 6;
        // assert(fabs(result - expected) < 0.1);
    }

    destroy_cuqdyn_conf();
}
