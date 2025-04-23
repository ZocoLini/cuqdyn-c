#ifndef EDO_SOLVER_H
#define EDO_SOLVER_H

#include <nvector_old/nvector_serial.h> /* access to serial N_Vector            */
#include <sundials_old/sundials_direct.h>

typedef struct
{
    int number_eq;
    void *f;
    N_Vector initial_values;
    realtype t0;
} ODEModel;

ODEModel create_ode_model(int number_eq, void *f, N_Vector initial_values, realtype t0);
void destroy_ode_model(ODEModel);

typedef struct
{
    realtype tf;
    realtype tinc;
    realtype first_output_time;
} TimeConstraints;

TimeConstraints create_time_constraints(realtype, realtype, realtype);
int time_constraints_steps(TimeConstraints);

typedef struct
{
    realtype scalar_rtol;
    N_Vector abs_tol;
} Tolerances;

Tolerances create_tolerances(realtype, realtype *, ODEModel);
void destroy_tolerances(Tolerances);

DlsMat solve_ode(N_Vector, ODEModel, TimeConstraints, Tolerances);

#endif //EDO_SOLVER_H
