#ifndef CONFIG_H
#define CONFIG_H

#include <sundials_old/sundials_nvector.h>

#include "cuqdyn.h"

typedef struct
{
    Tolerances tolerances;
} cuqdyn_conf;

cuqdyn_conf* init_cuqdyn_conf_from_file(const char *filename);
cuqdyn_conf* get_cuqdyn_conf();
void destroy_cuqdyn_conf();

#endif //CONFIG_H
