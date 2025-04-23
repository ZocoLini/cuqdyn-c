#include <assert.h>
#include <config.h>
#include <cuqdyn.h>
#include <math.h>
#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <time.h>

#include "functions/lotka_volterra.h"
#include "ode_solver.h"

int basic_f(realtype t, N_Vector y, N_Vector ydot, void *user_data);
void test_basic_ode();
void test_lotka_volterra();

int main(void)
{
    test_basic_ode();
    printf("\tTest 1 (dy/dx = 3/x * y; y(3) = 54) passed\n");

    test_lotka_volterra();
    printf("\tTest 2 (Lotka-Volterra α = γ = 0.5, β = δ = 0.02 and y(0) = (10, 5)) passed\n");

    return 0;
}

/* f => dy/dx = 3/x * y; y(3) = 54 */

void test_basic_ode()
{
    realtype *abs_tol = (realtype[]){1.0e-12};
    N_Vector abs_tol_vec = N_VNew_Serial(1, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_tol_vec);

    const TimeConstraints time_constraints = create_time_constraints(4.0, 5.0, 0.1);
    const Tolerances tolerances = create_tolerances(1.0e-12, abs_tol_vec);

    CuqdynConf *cuqdyn_conf = create_cuqdyn_conf(tolerances, time_constraints);
    set_cuqdyn_conf(cuqdyn_conf);

    N_Vector parameters = N_VNew_Serial(1, get_sun_context());
    NV_Ith_S(parameters, 0) = 3.0;

    N_Vector initial_values = N_VNew_Serial(1, get_sun_context());
    NV_Ith_S(initial_values, 0) = 54;

    const realtype t0 = 3.0;

    const ODEModel ode_model = create_ode_model(1, basic_f, initial_values, t0);
    DlsMat result = solve_ode(parameters, ode_model);

    assert(result != NULL);

    const int rows = SM_ROWS_D(result);
    const int cols = SM_COLUMNS_D(result);

    assert(cols == 2);
    assert(rows == 10);

    assert(fabs(SM_ELEMENT_D(result, 3, 0) - 4.3) < 0.0001);
    assert(fabs(SM_ELEMENT_D(result, 2, 1) - 148.176) < 0.0001);
    assert(fabs(SM_ELEMENT_D(result, 3, 1) - 159.014) < 0.0001);
    assert(fabs(SM_ELEMENT_D(result, 6, 1) - 194.672) < 0.0001);
    assert(fabs(SM_ELEMENT_D(result, 9, 1) - 235.298) < 0.0001);

    destroy_cuqdyn_conf(get_cuqdyn_conf());
    SUNMatDestroy(result);
    N_VDestroy(parameters);
    destroy_ode_model(ode_model);
}

int basic_f(realtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    N_Vector parameters = user_data;

    Ith(ydot, 1) = (Ith(parameters, 1) / t) * Ith(y, 1);

    return 0;
}

void test_lotka_volterra()
{
    realtype *abs_tol = (realtype[]) {1.0e-12, 1.0e-12};
    N_Vector abs_tol_vec = N_VNew_Serial(2, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_tol_vec);

    const TimeConstraints time_constraints = create_time_constraints(1.0, 5.0, 0.5);
    const Tolerances tolerances = create_tolerances(SUN_RCONST(1.0e-12), abs_tol_vec);

    CuqdynConf *cuqdyn_conf = create_cuqdyn_conf(tolerances, time_constraints);
    set_cuqdyn_conf(cuqdyn_conf);

    N_Vector parameters = N_VNew_Serial(4, get_sun_context());
    NV_Ith_S(parameters, 0) = 0.5;
    NV_Ith_S(parameters, 1) = 0.02;
    NV_Ith_S(parameters, 2) = 0.5;
    NV_Ith_S(parameters, 3) = 0.02;

    N_Vector initial_values = N_VNew_Serial(2, get_sun_context());
    NV_Ith_S(initial_values, 0) = 10;
    NV_Ith_S(initial_values, 1) = 5;

    const realtype t0 = 0.0;

    const ODEModel ode_model = create_ode_model(2, lotka_volterra_f, initial_values, t0);
    DlsMat result = solve_ode(parameters, ode_model);

    assert(result != NULL);

    const int rows = SM_ROWS_D(result);
    const int cols = SM_COLUMNS_D(result);

    assert(cols == 3);
    assert(rows == 8);

    assert(fabs(SM_ELEMENT_D(result, 0, 0) - 1.0) < 0.0001);
    assert(fabs(SM_ELEMENT_D(result, 0, 1) - 15.10) < 0.01);
    assert(fabs(SM_ELEMENT_D(result, 0, 2) - 3.883) < 0.001);
    assert(fabs(SM_ELEMENT_D(result, 6, 1) - 53.79) < 0.01);
    assert(fabs(SM_ELEMENT_D(result, 6, 2) - 5.456) < 0.001);

    destroy_cuqdyn_conf(get_cuqdyn_conf());
    SUNMatDestroy(result);
    N_VDestroy(parameters);
    destroy_ode_model(ode_model);
}
