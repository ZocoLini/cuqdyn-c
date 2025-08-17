#ifndef EDO_SOLVER_H
#define EDO_SOLVER_H

#include <nvector/nvector_serial.h>
#include <sundials/sundials_types.h>
#include <sundials/sundials_matrix.h>
#include "cuqdyn.h"

TransposedStates solve_ode(N_Vector parameters, N_Vector initial_values, sunrealtype t0, N_Vector times);

#endif //EDO_SOLVER_H
