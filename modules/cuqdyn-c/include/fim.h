#ifndef FIM_H
#define FIM_H

#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

/// Parameterization used to build the Fisher Information / Gauss-Newton matrix.
typedef enum
{
    FIM_PARAM_NATURAL = 0,
    FIM_PARAM_LOG = 1,
} FimParameterization;

/// How the covariance is obtained from the residual Jacobian.
typedef enum
{
    FIM_COV_RELATIVE_RIDGE = 0,
    FIM_COV_SVD_PINV = 1,
} FimCovarianceMethod;

typedef struct
{
    FimParameterization parameterization;
    FimCovarianceMethod covariance_method;
    double relative_ridge;
    double rank_tol_factor;
    double weak_fraction_threshold;
} FimOptions;

/// Defaults mirroring cuqdyn_default_options().fim in the Matlab toolbox.
FimOptions fim_default_options();

typedef struct
{
    /// Parameter covariance in natural units. Always populated.
    SUNMatrix cov_p;
    /// Parameter covariance in log units. NULL when the natural parameterization is used.
    SUNMatrix cov_log;
    /// Singular values of the Jacobian in the configured parameterization, descending.
    N_Vector singular_values;
    /// Right singular vectors, needed for the weak-direction diagnostics.
    SUNMatrix v;

    int rank;
    int n_weak;
    double ridge;
    double sigma2;
    double rank_tolerance;
    double condition_number;
    FimParameterization parameterization;
} FimResult;

/*
 * Rank-aware FIM / Gauss-Newton parameter covariance.
 *
 * j_nat  Jacobian of the weighted residuals with respect to the natural
 *        parameters, sized n_residuals x n_params.
 * sigma2 Residual variance scale (1.0 when the measurement sigmas are known).
 * theta  Best-fit parameter vector, length n_params.
 *
 * Returns NULL if the inputs are inconsistent or the linear algebra fails.
 * The caller owns the result and must release it with destroy_fim_result().
 */
FimResult *cuqdyn_fim_covariance(SUNMatrix j_nat, double sigma2, N_Vector theta, FimOptions options);

void destroy_fim_result(FimResult *result);

/*
 * Hybrid covariance: FIM marginal scale with the correlation structure taken
 * from the leave-one-out parameter ensemble.
 *
 *     Cov_hyb = D_FIM . R_LOO . D_FIM
 *
 * The motivation is that the FIM usually gets the variance scale about right
 * while its correlations are questionable, and the LOO ensemble supplies an
 * empirical correlation structure. The LOO covariance is not used as the scale
 * itself: dropping one of m informative points barely moves the optimum, so it
 * underestimates the true estimation variance by a factor of O(m).
 *
 * cov_fim is n_params x n_params; loo_params is one row per leave-one-out
 * refit. Returns a matrix the caller owns, or NULL on inconsistent input.
 */
SUNMatrix cuqdyn_hybrid_covariance(SUNMatrix cov_fim, SUNMatrix loo_params);

/*
 * Residual variance scale, mirroring cuqdyn_residual_variance.m: it is exactly
 * 1.0 when the residuals were divided by known measurement sigmas, and the
 * usual unbiased estimate otherwise.
 */
double cuqdyn_residual_variance(const double *weighted_residuals, long n_residuals, int n_params,
                                int sigma_is_known);

#endif // FIM_H
