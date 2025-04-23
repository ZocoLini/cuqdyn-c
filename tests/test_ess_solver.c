#define EXAMPLE_CONF_FILE "data/example_ess_config.xml"
#define LOTKA_VOLTERRA_CONF_FILE "data/lotka_volterra_ess_config.xml"
#define BBOB_CONF_FILE "data/TEMPLATE_BBOB.xml"
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

void test_example();
void lotka_volterra_ess();

void* examplefunction(double *x, void *data) {
    // Initialize mandatory structs
    experiment_total *exp1;
    output_function *res;
    int dim;
    exp1 = (experiment_total *) data;
    res = NULL;
    res = (output_function *) calloc(1,sizeof(output_function));
    dim = (*exp1).test.bench.dim;
    // Objective function code: in this example Schwefel
    double y, sum;
    int i;
    sum = 0.0;
    for (i=0;i<dim;i++){
        sum = sum + x[i]*sin(sqrt(abs(x[i])));
    }
    y = 418.9829*dim - sum;
    // Return fx: set the fx in output_function struct
    // and return like a void pointer
    res->value = y;

    return res;
}

/*
* function [J,g,R]=prob_mod_lv(x,texp,yexp)
* [tout,yout] = ode15s(@prob_mod_dynamics_lv,texp,[10,5],odeset('RelTol',1e-6,'AbsTol',1e-6*ones(1,2)),x);
* R=(yout-yexp);
* R=reshape(R,numel(R),1);
* J = sum(sum((yout-yexp).^2));
* g=0;
return
*/

int main(int argc, char** argv)
{
#ifdef MPI2
    int err = MPI_Init(&argc, &argv);

    if (err != MPI_SUCCESS) {
        fprintf(stderr, "MPI_Init failed\n");
        exit(1);
    }
#endif

    test_example();
    printf("\tTest 1 passed\n");

    lotka_volterra_ess();
    printf("\tTest 2 passed\n");

    return 0;
}

void test_example()
{
    // I don't know the real values, these are the returned values the test returned for the first time
    realtype expected[10] = {422, 422, 422, 422, 422, 422, 422, 422, 422, 422};

    N_Vector texp = N_VNew_Serial(0, get_sun_context());
    DlsMat yexp = SUNDenseMatrix(0, 0, get_sun_context());

    realtype *xbest = execute_ess_solver(EXAMPLE_CONF_FILE, OUPUT_PATH, examplefunction, texp, yexp);

    for (int i = 0; i < 10; ++i)
    {
        assert(fabs(xbest[i] - expected[i]) < 3);
    }
}

void lotka_volterra_ess()
{
    realtype *abs_tol = (realtype[]){1.0e-8, 1.0e-8};
    N_Vector abs_tol_vec = N_VNew_Serial(2, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_tol_vec);

    const TimeConstraints time_constraints = create_time_constraints(1.0, 30.0, 1.0);
    const Tolerances tolerances = create_tolerances(SUN_RCONST(1.0e-6), abs_tol_vec);
    CuqdynConf *cuqdyn_conf = create_cuqdyn_conf(tolerances, time_constraints);

    set_cuqdyn_conf(cuqdyn_conf);

    realtype expected[4] = { 0.5, 0.02, 0.5, 0.02 };

    N_Vector texp = N_VNew_Serial(0, get_sun_context());
    DlsMat yexp = SUNDenseMatrix(0, 0, get_sun_context());

    realtype *xbest = execute_ess_solver(LOTKA_VOLTERRA_CONF_FILE, OUPUT_PATH, lotka_volterra_obj_f, texp, yexp);

    for (int i = 0; i < 4; ++i)
    {
        assert(fabs(xbest[i] - expected[i]) < 0.1);
    }
}