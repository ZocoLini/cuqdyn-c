#ifndef FUNCTIONS_H
#define FUNCTIONS_H

#include <cvodes_old/cvodes.h>

typedef int (*OdeModelFun)(realtype, N_Vector, N_Vector, void*);
typedef void *(*ObjFunc)(double *, void *);

#endif //FUNCTIONS_H
