#ifndef ESS_SOLVER_H
#define ESS_SOLVER_H

/// Executes the ESS solver for a given sacess config file using the given objective function.
/// texp, yexp and initial_values are arguments needed to execute certain objective functions, like
/// the one defined in lotka_volterra.c.
/// rank and nproc are used to define the rank of the process and the number of processes in a MPI environment.
N_Vector execute_ess_solver(const char *config_file, const char *output,
  N_Vector texp, DlsMat yexp, N_Vector initial_values, int rank, int nproc);

#endif //ESS_SOLVER_H
