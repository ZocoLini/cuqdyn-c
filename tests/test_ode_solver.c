#include <assert.h>
#include <config.h>
#include <cuqdyn.h>
#include <math.h>
#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <time.h>

#include "../modules/cuqdyn-c/include/functions.h"
#include "ode_solver.h"

void test_lotka_volterra();

int main(void)
{
    test_lotka_volterra();
    printf("\tTest 2 (Lotka-Volterra α = γ = 0.5, β = δ = 0.02 and y(0) = (10, 5)) passed\n");

    return 0;
}

void test_lotka_volterra()
{
    realtype *abs_tol = (realtype[]) {1.0e-12, 1.0e-12};
    N_Vector abs_tol_vec = N_VNew_Serial(2, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_tol_vec);

    init_cuqdyn_conf_from_file("data/lotka_volterra_cuqdyn_config.xml");

    N_Vector times = N_VNew_Serial(9, get_sun_context());
    NV_Ith_S(times, 0) = 1.0;
    NV_Ith_S(times, 1) = 1.5;
    NV_Ith_S(times, 2) = 2.0;
    NV_Ith_S(times, 3) = 2.5;
    NV_Ith_S(times, 4) = 3.0;
    NV_Ith_S(times, 5) = 3.5;
    NV_Ith_S(times, 6) = 4.0;
    NV_Ith_S(times, 7) = 4.5;
    NV_Ith_S(times, 8) = 5.0;

    N_Vector parameters = N_VNew_Serial(4, get_sun_context());
    NV_Ith_S(parameters, 0) = 0.5;
    NV_Ith_S(parameters, 1) = 0.02;
    NV_Ith_S(parameters, 2) = 0.5;
    NV_Ith_S(parameters, 3) = 0.02;

    N_Vector initial_values = N_VNew_Serial(2, get_sun_context());
    NV_Ith_S(initial_values, 0) = 10;
    NV_Ith_S(initial_values, 1) = 5;

    const realtype t0 = 0.0;

    const ODEModel ode_model = create_ode_model(2, initial_values, t0, times);
    DlsMat result = solve_ode(parameters, ode_model);

    assert(result != NULL);

    const int rows = SM_ROWS_D(result);
    const int cols = SM_COLUMNS_D(result);

    assert(cols == 3);
    assert(rows == 9);

    assert(fabs(SM_ELEMENT_D(result, 0, 0) - 1.0) < 0.0001);
    assert(fabs(SM_ELEMENT_D(result, 0, 1) - 15.10) < 0.01);
    assert(fabs(SM_ELEMENT_D(result, 0, 2) - 3.883) < 0.001);
    assert(fabs(SM_ELEMENT_D(result, 6, 1) - 53.79) < 0.01);
    assert(fabs(SM_ELEMENT_D(result, 6, 2) - 5.456) < 0.001);

    destroy_cuqdyn_conf();
    SUNMatDestroy(result);
    N_VDestroy(parameters);
    destroy_ode_model(ode_model);
}
