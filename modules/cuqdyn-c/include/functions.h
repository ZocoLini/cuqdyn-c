#ifndef CUQDYN_FUNCTIONS_H
#define CUQDYN_FUNCTIONS_H
#include <sundials/sundials_direct.h>
#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

#include "config.h"

/// Function used to solve the ODE using cvodes
int ode_model_fun(sunrealtype t, N_Vector y, N_Vector ydot, void *data);

/*
 * Analytic Jacobian df/dy of ode_model_fun, for CVodeSetJacFn. Only valid when
 * has_jacobian() says the model has one; otherwise CVODES keeps its finite
 * differences.
 */
int ode_model_jac(sunrealtype t, N_Vector y, N_Vector fy, SUNMatrix J, void *user_data, N_Vector tmp1, N_Vector tmp2,
                  N_Vector tmp3);

/// 1 when the model of the context has an analytic Jacobian.
extern int has_jacobian(CuqDynContext context);

/*
 * Weighted least-squares objective used by the sacess library, restricted to
 * the observed states. Reduces to plain least squares when every state is
 * measured and no residual weighting is configured.
 */
void *obj_func(double *x, void *data);

/// Residual weight applied to the given observed state, per the residual model.
sunrealtype cuqdyn_residual_weight(const CostOptions *cost, int observed_state);

#endif // CUQDYN_FUNCTIONS_H
