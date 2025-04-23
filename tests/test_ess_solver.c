#define EXAMPLE_CONF_FILE "data/example_ess_config.xml"
#define LOTKA_VOLTERRA_CONF_FILE "data/lotka_volterra_ess_config.xml"
#define BBOB_CONF_FILE "data/TEMPLATE_BBOB.xml"
#define OUPUT_PATH "data/ess_output"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <tgmath.h>

#include "ess_solver.h"
#include "cuqdyn.h"
#include "functions/lotka_volterra.h"
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

void* lotka_volterra_obj_f(double *x, void *data)
{
    output_function *res = calloc(1, sizeof(output_function));

    // Defining yexp:
    DlsMat yexp = SUNDenseMatrix(30, 2, get_sun_context());

    realtype yexp_data[30][2] = {
        {16.4161, 2.14078},
        {26.9327, 6.95752},
        {36.199, 3.05692},
        {53.5232, 8.01177},
        {75.279, 12.5015},
        {78.8885, 39.1838},
        {37.4748, 78.3761},
        {10.2444, 80.1333},
        {2.91173, 58.1003},
        {4.31927, 34.5728},
        {5.77477, 22.452},
        {3.02048, 15.9231},
        {6.87234, 12.3715},
        {7.02391, 8.00952},
        {11.5876, 3.70516},
        {11.6953, 5.03891},
        {24.0456, 1.8209},
        {34.2654, 2.18679},
        {54.8232, 5.018},
        {74.3034, 9.68863},
        {83.3479, 37.7167},
        {45.6403, 78.4525},
        {10.0775, 80.2856},
        {6.10055, 57.703},
        {6.33843, 39.9109},
        {5.36425, 22.9151},
        {2.84835, 15.7364},
        {9.82992, 12.7098},
        {8.26545, 2.91747},
        {7.38187, 6.32052}
    };

    for (int i = 0; i < 30; ++i) {
        for (int j = 0; j < 2; ++j) {
            SM_ELEMENT_D(yexp, i, j) = yexp_data[i][j];
        }
    }

    // Solving the ODE to use in the objetive function
    N_Vector initial_values = N_VNew_Serial(2, get_sun_context());
    NV_Ith_S(initial_values, 0) = 10;
    NV_Ith_S(initial_values, 1) = 5;

    N_Vector parameters = N_VNew_Serial(4, get_sun_context());
    NV_Ith_S(parameters, 0) = x[0];
    NV_Ith_S(parameters, 1) = x[1];
    NV_Ith_S(parameters, 2) = x[2];
    NV_Ith_S(parameters, 3) = x[3];

    const realtype t0 = 0.0;

    const ODEModel ode_model = create_ode_model(2, lotka_volterra_f, initial_values, t0);
    const TimeConstraints time_constraints = create_time_constraints(1.0, 30.0, 1.0);
    const Tolerances tolerances = create_tolerances(SUN_RCONST(1.0e-6), (realtype[]){1.0e-8, 1.0e-8}, ode_model);

    DlsMat result = solve_ode(parameters, ode_model, time_constraints, tolerances);

    // Objective function code:
    realtype J = 0.0;
    long int rows = SM_ROWS_D(result);
    long int cols = SM_COLUMNS_D(result);

    for (long int i = 0; i < rows; ++i) {
        for (long int j = 1; j < cols; ++j) {
            realtype diff = SM_ELEMENT_D(result, i, j) - SM_ELEMENT_D(yexp, i, j - 1);
            J += diff * diff;
        }
    }

    // Free resources
    N_VDestroy(parameters);
    destroy_ode_model(ode_model);
    // The vector inside tolerances is beeing destroyed by the solve_ode_function when it frees CVode
    // destroy_tolerances(tolerances);
    SUNMatDestroy(result);
    SUNMatDestroy(yexp);

    res->value = J;

    return res;
}

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

    realtype *xbest = execute_ess_solver(EXAMPLE_CONF_FILE, OUPUT_PATH, examplefunction);

    for (int i = 0; i < 10; ++i)
    {
        assert(fabs(xbest[i] - expected[i]) < 3);
    }
}

void lotka_volterra_ess()
{
    realtype expected[4] = { 0.5, 0.02, 0.5, 0.02 };

    realtype *xbest = execute_ess_solver(LOTKA_VOLTERRA_CONF_FILE, OUPUT_PATH, lotka_volterra_obj_f);

    for (int i = 0; i < 4; ++i)
    {
        assert(fabs(xbest[i] - expected[i]) < 0.1);
    }
}