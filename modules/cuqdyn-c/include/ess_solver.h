#ifndef ESS_SOLVER_H
#define ESS_SOLVER_H
#include <sundials/sundials_matrix.h>

#ifdef MPI
#include <mpi.h>

/// Ranks a sacess run is spread over.
typedef MPI_Comm EssComm;
#define ESS_COMM_WORLD MPI_COMM_WORLD
#else
/// Placeholder so the signature is the same in every build; a serial run uses one rank.
typedef int EssComm;
#define ESS_COMM_WORLD 0
#endif

/// Executes the ESS solver for a given sacess config file using the given objective function.
/// texp, yexp and initial_condition are arguments needed to execute the objective functions, like
/// the one defined in functions.c.
/// observed_idx declares which model state each row of yexp measures.
/// comm is the group of ranks this run gets; ESS_COMM_WORLD gives it every rank.
N_Vector execute_ess_solver(const char *config_file, const char *output, N_Vector texp, SUNMatrix yexp,
                            N_Vector initial_condition, N_Vector initial_params, int *observed_idx, EssComm comm);

#endif // ESS_SOLVER_H
