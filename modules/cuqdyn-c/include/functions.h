#ifndef LOTKA_VOLTERRA_H
#define LOTKA_VOLTERRA_H
#include <sundials_old/sundials_direct.h>
#include <sundials_old/sundials_nvector.h>

/// Function used to solve the ODE using cvodes
int ode_model_fun(realtype t, N_Vector y, N_Vector ydot, void *data);
/// Objetive function for the lotka_volterra problem used by the sacess library
void* ode_model_obj_func(double *x, void *data);

#endif //LOTKA_VOLTERRA_H
