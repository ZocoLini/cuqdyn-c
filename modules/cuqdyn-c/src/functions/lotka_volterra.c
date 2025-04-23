#include <sundials_old/sundials_nvector.h>
#include <method_module/structure_paralleltestbed.h>

#include "cuqdyn.h"

int lotka_volterra_f(realtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    realtype y1, y2;

    y1 = Ith(y, 1);
    y2 = Ith(y, 2);

    realtype *data = N_VGetArrayPointer(user_data);

    Ith(ydot, 1) = y1 * (SUN_RCONST(data[0]) - SUN_RCONST(data[1]) * y2);
    Ith(ydot, 2) = -y2 * (SUN_RCONST(data[2]) - SUN_RCONST(data[3]) * y1);

    return (0);
}

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

    DlsMat result = solve_ode(parameters, ode_model);

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