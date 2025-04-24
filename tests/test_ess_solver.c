#define LOTKA_VOLTERRA_CONF_FILE "data/lotka_volterra_ess_config.xml"
#define OUPUT_PATH "data/ess_output"

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

int main(int argc, char** argv)
{
#ifdef MPI2
    int err = MPI_Init(&argc, &argv);

    if (err != MPI_SUCCESS) {
        fprintf(stderr, "MPI_Init failed\n");
        exit(1);
    }
#endif

    lotka_volterra_ess();
    printf("\tTest 1 passed\n");

    return 0;
}

void lotka_volterra_ess()
{
    realtype *abs_tol = (realtype[]){1.0e-8, 1.0e-8};
    N_Vector abs_tol_vec = N_VNew_Serial(2, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_tol_vec);

    const TimeConstraints time_constraints = create_time_constraints(1.0, 30.0, 1.0);
    const Tolerances tolerances = create_tolerances(SUN_RCONST(1.0e-6), abs_tol_vec);
    init_cuqdyn_conf(tolerances, time_constraints);

    realtype expected[4] = { 0.5, 0.02, 0.5, 0.02 };

    N_Vector texp = N_VNew_Serial(0, get_sun_context());
    DlsMat yexp = SUNDenseMatrix(0, 0, get_sun_context());

    realtype *xbest = execute_ess_solver(LOTKA_VOLTERRA_CONF_FILE, OUPUT_PATH, lotka_volterra_obj_f, texp, yexp);

    for (int i = 0; i < 4; ++i)
    {
        assert(fabs(xbest[i] - expected[i]) < 0.1);
    }

    destroy_cuqdyn_conf();
}