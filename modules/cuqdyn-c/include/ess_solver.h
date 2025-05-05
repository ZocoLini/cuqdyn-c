#ifndef ESS_SOLVER_H
#define ESS_SOLVER_H

/// Executes the ESS solver for a given sacess config file using the given objective function.
/// texp, yexp and initial_values are arguments needed to execute certain objective functions, like
/// the one defined in lotka_volterra.c
N_Vector execute_ess_solver(const char *config_file, const char *output, ObjFunc obj_func,
  N_Vector texp, DlsMat yexp, N_Vector initial_values);

#endif //ESS_SOLVER_H
