#ifndef CONFIG_H
#define CONFIG_H

#include <sundials_old/sundials_nvector.h>

#include "cuqdyn.h"

typedef struct
{
    realtype tf;
    realtype tinc;
    realtype first_output_time;
} TimeConstraints;

TimeConstraints create_time_constraints(realtype, realtype, realtype);
int time_constraints_steps(TimeConstraints);

typedef struct
{
    realtype scalar_rtol;
    N_Vector abs_tol;
} Tolerances;

Tolerances create_tolerances(realtype rtol, N_Vector atol);
void destroy_tolerances(Tolerances);

typedef struct
{
    Tolerances tolerances;
    TimeConstraints time_constraints;
} CuqdynConf;

CuqdynConf *init_cuqdyn_conf_from_file(const char *filename);
CuqdynConf *init_cuqdyn_conf(Tolerances tolerances, TimeConstraints time_constraints);
void destroy_cuqdyn_conf();
CuqdynConf * get_cuqdyn_conf();

#endif //CONFIG_H
