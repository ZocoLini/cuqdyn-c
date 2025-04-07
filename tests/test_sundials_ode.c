//
// Created by borja on 4/7/25.
//

#include <lib.h>
#include <sundials/sundials_matrix.h>
#include <time.h>

int basic_f(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data);
void test_basic_ode();

int main(void)
{
    test_basic_ode();
    printf("\tTest 1 (dy/dx = 3/x * y; y(3) = 54) passed\n");
    return 0;
}

/* f => dy/dx = 3/x * y; y(3) = 54 */

void test_basic_ode()
{
    SUNContext sunctx;
    SUNContext_Create(SUN_COMM_NULL, &sunctx);

    N_Vector parameters = N_VNew_Serial(1, sunctx);
    N_VGetArrayPointer(parameters)[0] = 3.0;

    N_Vector initial_values = N_VNew_Serial(1, sunctx);
    N_VGetArrayPointer(initial_values)[0] = 54;

    N_Vector times = N_VNew_Serial(1, sunctx);
    N_VGetArrayPointer(times)[0] = 3.0;

    ODEModel ode_model = create_ode_model(1, basic_f, initial_values, times);
    TimeConstraints time_constraints = create_time_constraints(4.0, 5.0, 0.1);
    Tolerances tolerances = create_tolerances(SUN_RCONST(1.0e-8), (sunrealtype[]){1.0e-8}, ode_model, sunctx);

    SUNMatrix result = solve_ode(parameters, ode_model, time_constraints, tolerances, sunctx);

    sunrealtype *data = SM_DATA_D(result);
    int rows = SM_ROWS_D(result);
    int cols = SM_COLUMNS_D(result);

    assert(cols == 2);
    assert(rows == 10);

    assert(abs(data[cols * 3] - 4.3) < 0.0001);
    assert(abs(data[cols * 2 + 1] - 148.176) < 0.001);
    assert(abs(data[cols * 3 + 1] - 159.014) < 0.001);
    assert(abs(data[cols * 6 + 1] - 194.672) < 0.001);
    assert(abs(data[cols * 9 + 1] - 235.298) < 0.001);
}

int basic_f(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    N_Vector parameters = user_data;

    NV_Ith_S(ydot, 0) = (Ith(parameters, 1) / t) * Ith(y, 1);

    return 0;
}
