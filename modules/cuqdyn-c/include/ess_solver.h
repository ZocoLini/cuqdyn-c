#ifndef ESS_SOLVER_H
#define ESS_SOLVER_H

N_Vector execute_ess_solver(const char *file, const char *path, ObjFunc obj_func, N_Vector texp, DlsMat yexp);

#endif //ESS_SOLVER_H
