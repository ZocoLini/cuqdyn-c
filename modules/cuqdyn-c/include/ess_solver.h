#ifndef ESS_SOLVER_H
#define ESS_SOLVER_H
#include <sundials/sundials_matrix.h>

/// Executes the ESS solver for a given sacess config file using the given objective function.
/// texp, yexp and initial_condition are arguments needed to execute the objective functions, like
/// the one defined in functions.c.
/// rank and nproc are used to define the rank of the process and the number of processes in an MPI environment.
N_Vector execute_ess_solver(const char *config_file, const char *output,
  N_Vector texp, SUNMatrix yexp, N_Vector initial_condition, N_Vector initial_params);

#endif //ESS_SOLVER_H
