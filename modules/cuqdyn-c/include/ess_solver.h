#ifndef ESS_SOLVER_H
#define ESS_SOLVER_H
#include <sundials_old/sundials_direct.h>

double *execute_ess_solver(const char *file, const char *path, void *(*obj_func)(double *, void *));

#endif //ESS_SOLVER_H
