#ifndef EDO_SOLVER_H
#define EDO_SOLVER_H

#include <functions/functions.h>
#include <nvector_old/nvector_serial.h>
#include <sundials_old/sundials_direct.h>

typedef struct
{
    int number_eq;
    OdeModelFun f;
    N_Vector initial_values;
    realtype t0;
    N_Vector times;
} ODEModel;

ODEModel create_ode_model(int number_eq, OdeModelFun f, N_Vector initial_values, realtype t0, N_Vector times);
void destroy_ode_model(ODEModel);

DlsMat solve_ode(N_Vector, ODEModel);

#endif //EDO_SOLVER_H
