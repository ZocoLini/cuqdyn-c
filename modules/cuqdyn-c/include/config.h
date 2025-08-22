#ifndef CONFIG_H
#define CONFIG_H

typedef struct
{
    double rtol;
    int atol_len;
    double *atol;

} Tolerances;

typedef struct
{
    int y_count;
    int p_count;
    char **exprs;
} OdeExpr;

typedef struct
{
    int len;
    double *array;
} Y0;

typedef struct
{
    int count;
    char **exprs;
} StatesTransformer;

typedef struct
{
    Tolerances tolerances;
    OdeExpr ode_expr;
    double time_scaling;
    Y0 y0;
    StatesTransformer states_transformer;
} CuqdynConf;

typedef void *CuqDynContext;

CuqDynContext init_cuqdyn_context_from_file(const char *filename);
CuqDynContext get_cuqdyn_context();

extern CuqdynConf *get_cuqdyn_conf(CuqDynContext context);
extern void destroy_cuqdyn_context(CuqDynContext context);

#endif // CONFIG_H
