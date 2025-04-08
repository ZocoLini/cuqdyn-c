#ifndef LOTKA_VOLTERRA_H
#define LOTKA_VOLTERRA_H
#include <sundials/sundials_nvector.h>

int lotka_volterra_f(sunrealtype, N_Vector, N_Vector , void *);

#endif //LOTKA_VOLTERRA_H
