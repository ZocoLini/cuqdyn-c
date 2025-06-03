#ifndef EDO_SOLVER_H
#define EDO_SOLVER_H

#include <nvector/nvector_serial.h>
#include <sundials/sundials_types.h>
#include <sundials/sundials_matrix.h>
/*
 * Solves an ODE system defined by a ODEModel struct using a vector of parameters.
 *
 * Returns:
 *   SUNMatrix where:
 *   - Each row corresponds to a time point
 *   - Column 0: Time values (t)
 *   - Columns 1-n: Solution components (y1, y2, ..., yn)
 *
 */
SUNMatrix solve_ode(N_Vector parameters, N_Vector initial_values, sunrealtype t0, N_Vector times);

#endif //EDO_SOLVER_H
