#ifndef EDO_SOLVER_H
#define EDO_SOLVER_H

#include <nvector_old/nvector_serial.h>
#include <sundials_old/sundials_direct.h>
/*
 * Solves an ODE system defined by a ODEModel struct using a vector of parameters.
 *
 * Returns:
 *   DlsMat where:
 *   - Each row corresponds to a time point
 *   - Column 0: Time values (t)
 *   - Columns 1-n: Solution components (y1, y2, ..., yn)
 *
 */
DlsMat solve_ode(N_Vector parameters, N_Vector initial_values, realtype t0, N_Vector times);

#endif //EDO_SOLVER_H
