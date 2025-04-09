#ifndef EDO_SOLVER_H
#define EDO_SOLVER_H

#include <nvector/nvector_serial.h> /* access to serial N_Vector            */
#include <sunlinsol/sunlinsol_dense.h> /* access to dense SUNLinearSolver      */

typedef struct
{
    int number_eq;
    void *f;
    N_Vector initial_values;
    sunrealtype t0;
} ODEModel;

ODEModel create_ode_model(int number_eq, void *f, N_Vector initial_values, sunrealtype t0);

typedef struct
{
    sunrealtype tf;
    sunrealtype tinc;
    sunrealtype first_output_time;
} TimeConstraints;

TimeConstraints create_time_constraints(sunrealtype, sunrealtype, sunrealtype);
int time_constraints_steps(TimeConstraints);

typedef struct
{
    sunrealtype scalar_rtol;
    N_Vector abs_tol;
} Tolerances;

Tolerances create_tolerances(sunrealtype, sunrealtype *, ODEModel);

SUNMatrix solve_ode(N_Vector, ODEModel, TimeConstraints, Tolerances);

#endif //EDO_SOLVER_H
