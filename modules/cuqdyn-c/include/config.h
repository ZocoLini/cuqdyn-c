#ifndef CONFIG_H
#define CONFIG_H

#include <sundials_old/sundials_nvector.h>

#include "cuqdyn.h"

typedef struct
{
    Tolerances tolerances;
    TimeConstraints time_constraints;
} CuqdynConf;

CuqdynConf* create_cuqdyn_conf(Tolerances tolerances, TimeConstraints time_constraints);
void destroy_cuqdyn_conf(CuqdynConf *cuqdyn_conf);

CuqdynConf* init_cuqdyn_conf_from_file(const char *filename);
void set_cuqdyn_conf(CuqdynConf *cuqdyn_conf);
CuqdynConf* get_cuqdyn_conf();

#endif //CONFIG_H
