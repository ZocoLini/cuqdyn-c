#ifndef LOTKA_VOLTERRA_H
#define LOTKA_VOLTERRA_H
#include <sundials/sundials_direct.h>
#include <sundials/sundials_nvector.h>

/// Function used to solve the ODE using cvodes
int ode_model_fun(sunrealtype t, N_Vector y, N_Vector ydot, void *data);
/// Objetive functions used by the sacess library
void *obj_func(double *x, void *data);
void *obj_func2(double *x, void *data);

#endif // LOTKA_VOLTERRA_H
