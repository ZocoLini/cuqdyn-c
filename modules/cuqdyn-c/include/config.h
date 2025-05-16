#ifndef CONFIG_H
#define CONFIG_H

#include <sundials_old/sundials_nvector.h>

typedef struct
{
    realtype rtol;
    N_Vector atol;

} Tolerances;

Tolerances create_tolerances(realtype rtol, N_Vector atol);
void destroy_tolerances(Tolerances);

typedef struct
{
    int y_count;
    int p_count;
    char** exprs;
} OdeExpr;

OdeExpr create_ode_expr(int y_count, int p_count, char** exprs);
void destroy_ode_expr(OdeExpr ode_expr);

typedef struct
{
    Tolerances tolerances;
    OdeExpr ode_expr;
} CuqdynConf;

CuqdynConf *init_cuqdyn_conf_from_file(const char *filename);
int parse_cuqdyn_conf(const char* filename, CuqdynConf* config);
CuqdynConf *init_cuqdyn_conf(Tolerances tolerances);
void destroy_cuqdyn_conf();
CuqdynConf * get_cuqdyn_conf();

#endif //CONFIG_H
