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
    char** exprs;
} OdeExpr;

typedef struct
{
    int len;
    double* array;
} Y0;

typedef struct
{
    int count;
    char** exprs;
} StatesTransformer;

typedef struct
{
    Tolerances tolerances;
    OdeExpr ode_expr;
    Y0 y0;
    StatesTransformer states_transformer;
} CuqdynConf;

extern CuqdynConf *load_cuqdyn_conf_from_file(const char *filename);
extern CuqdynConf *get_cuqdyn_conf();

#endif //CONFIG_H
