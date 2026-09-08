#ifndef CONFIG_H
#define CONFIG_H

/*
 * These structs mirror the #[repr(C)] definitions in cuqdyn-rs/src/context.rs
 * field for field. A change here needs the same change there; the layout is
 * exercised by comparing_rs_struct_to_c_struct_test on the Rust side.
 */

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

/// Residual error model, mirroring cuqdyn_weight_residuals.m.
typedef enum
{
    RESIDUAL_MODEL_NONE = 0,
    RESIDUAL_MODEL_KNOWN_SIGMA = 1,
    RESIDUAL_MODEL_STATE_WEIGHTS = 2,
} ResidualModel;

typedef struct
{
    int residual_model;
    int sigma_len;
    double *sigma;
    /// When set, residuals are already standardized and the FIM variance scale is 1.
    int sigma_is_known;
    double sigma_floor;
    int weights_len;
    double *weights;
} CostOptions;

typedef struct
{
    /// 0 = natural parameters, 1 = log parameters.
    int parameterization;
    double relative_ridge;
    double rank_tol_factor;
    double weak_fraction_threshold;
} FimConfigOptions;

typedef struct
{
    Tolerances tolerances;
    OdeExpr ode_expr;
    double time_scaling;
    Y0 y0;
    /// Predictive region level; bands are nominally 1 - 2*alp.
    double alp;
    CostOptions cost;
    FimConfigOptions fim;
} CuqdynConf;

typedef void *CuqDynContext;

CuqDynContext init_cuqdyn_context_from_file(const char *filename);
CuqDynContext get_cuqdyn_context();

extern CuqdynConf *get_cuqdyn_conf(CuqDynContext context);
extern void destroy_cuqdyn_context(CuqDynContext context);

#endif // CONFIG_H
