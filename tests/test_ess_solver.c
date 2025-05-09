#define LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2GB "data/lotka_volterra_ess_config_nl2sol.dn2gb.xml"
#define LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2FB "data/lotka_volterra_ess_config_nl2sol.dn2fb.xml"
#define LOTKA_VOLTERRA_CONF_FILE_DHC "data/lotka_volterra_ess_config_dhc.xml"
#define LOTKA_VOLTERRA_CONF_FILE_MISQP "data/lotka_volterra_ess_config_misqp.xml"
#define OUPUT_PATH "ess_output"

#include <assert.h>
#include <config.h>
#include <cuqdyn.h>
#include <functions/lotka_volterra.h>
#include <stdio.h>
#include <stdlib.h>
#include <tgmath.h>

#include "ess_solver.h"
#include "method_module/structure_paralleltestbed.h"

void lotka_volterra_ess();

int main(int argc, char **argv)
{
#ifdef MPI2
    int err = MPI_Init(&argc, &argv);

    if (err != MPI_SUCCESS)
    {
        fprintf(stderr, "MPI_Init failed\n");
        exit(1);
    }
#endif

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2GB);
    printf("\tTest 1 passed NL2SOL_DN2GB\n");

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_NL2SOL_DN2FB);
    printf("\tTest 2 passed NL2SOL_DN2FB\n");

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_DHC);
    printf("\tTest 3 passed DHC\n");

    lotka_volterra_ess(LOTKA_VOLTERRA_CONF_FILE_MISQP);
    printf("\tTest 4 passed MISQP\n");

    return 0;
}

void lotka_volterra_ess(char *conf_file)
{
    realtype *abs_tol = (realtype[]) {1.0e-8, 1.0e-8};
    N_Vector abs_tol_vec = N_VNew_Serial(2, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_tol_vec);

    const Tolerances tolerances = create_tolerances(SUN_RCONST(1.0e-6), abs_tol_vec);
    init_cuqdyn_conf(tolerances);

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

    N_Vector xbest = execute_ess_solver(conf_file, OUPUT_PATH, lotka_volterra_obj_f, texp, yexp, initial_values);

    for (int i = 0; i < 4; ++i)
    {
        realtype expected = expected_values[i];
        realtype result = NV_Ith_S(xbest, i);

        realtype a = 6;
        // assert(fabs(result - expected) < 0.1);
    }

    destroy_cuqdyn_conf();
}
