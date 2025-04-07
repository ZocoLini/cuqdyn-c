//
// Created by borja on 4/7/25.
//

#include <lib.h>
#include <sundials/sundials_matrix.h>

int basic_f(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data);
void test_basic_ode();

int main(void)
{
    test_basic_ode();
    return 0;
}

/* f => dy/dx = 2/x * y; y(3) = 30*/

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

    SUNMatrix result = solve_ode(parameters, ode_model, sunctx);
}

int basic_f(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    sunrealtype yx = NV_Ith_S(y, 0);
    sunrealtype *data = N_VGetArrayPointer(user_data);
    NV_Ith_S(ydot, 0) = (data[0] / t) * yx;

    return 0;
}
