#include <gsl/gsl_cdf.h>
#include <math.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "cuqdyn.h"
#include "fim.h"
#include "functions.h"
#include "ode_solver.h"
#include "uq_bands.h"

/// Var[y_k(t_i)] = S_k(t_i) * Cov_p * S_k(t_i)', for every state and time.
static SUNMatrix propagate(const Sensitivities sensitivities, SUNMatrix covariance, const long n_states, const long m,
                           const int n_params)
{
    SUNMatrix std_y = NewDenseMatrix(n_states, m);

    for (long i = 0; i < m; ++i)
    {
        for (long k = 0; k < n_states; ++k)
        {
            double variance = 0.0;
            for (int p = 0; p < n_params; ++p)
            {
                for (int q = 0; q < n_params; ++q)
                {
                    variance += sensitivity_at(sensitivities, k, i, p) * SM_ELEMENT_D(covariance, p, q) *
                                sensitivity_at(sensitivities, k, i, q);
                }
            }
            SM_ELEMENT_D(std_y, k, i) = sqrt(variance > 0.0 ? variance : 0.0);
        }
    }

    return std_y;
}

/// True when the state carries measurements, and so gets conformal bands.
static int is_observed(const int *observed_idx, const int n_obs, const long state)
{
    for (int j = 0; j < n_obs; ++j)
    {
        if (observed_idx[j] == state)
        {
            return 1;
        }
    }
    return 0;
}

/*
 * One variety starts as a copy of the conformal base, so a state the data
 * measures reads the same in both and a covariance that cannot be built leaves
 * usable bands behind rather than an empty matrix.
 */
static void start_from_base(SUNMatrix q_low_base, SUNMatrix q_up_base, const long m, const long n_states, UqBands *out)
{
    out->q_low = NewDenseMatrix(m, n_states);
    out->q_up = NewDenseMatrix(m, n_states);
    SUNMatCopy(q_low_base, out->q_low);
    SUNMatCopy(q_up_base, out->q_up);
    out->cov_p = NULL;
    out->std_y = NULL;
}

/*
 * Rewrites the hidden states of one variety from its covariance. This is the
 * whole of what separates the two: same sensitivities, same quantile, same
 * centre, and the measured states are left as the conformal base put them.
 */
static void fill_from_covariance(const Sensitivities sensitivities, SUNMatrix covariance, TransposedStates media_tot,
                                 const int *observed_idx, const int n_obs, const double z, const long n_states,
                                 const long m, const int n_params, UqBands *out)
{
    // SM_ELEMENT_D does not parenthesise its argument, so the matrices are held
    // in locals rather than reached through out-> inside the macro.
    SUNMatrix std_y = propagate(sensitivities, covariance, n_states, m, n_params);
    SUNMatrix cov_p = NewDenseMatrix(n_params, n_params);
    SUNMatrix q_low = out->q_low;
    SUNMatrix q_up = out->q_up;

    SUNMatCopy(covariance, cov_p);

    for (long k = 0; k < n_states; ++k)
    {
        if (is_observed(observed_idx, n_obs, k))
        {
            continue; // conformal bands already cover this state
        }

        for (long i = 1; i < m; ++i)
        {
            const double centre = SM_ELEMENT_D(media_tot, k, i);
            const double half_width = z * SM_ELEMENT_D(std_y, k, i);
            SM_ELEMENT_D(q_low, i, k) = centre - half_width;
            SM_ELEMENT_D(q_up, i, k) = centre + half_width;
        }
    }

    out->cov_p = cov_p;
    out->std_y = std_y;
}

void conformal_only_bands(SUNMatrix q_low_base, SUNMatrix q_up_base, const long m, const long n_states,
                          UqBands *fim_out, UqBands *hybrid_out)
{
    start_from_base(q_low_base, q_up_base, m, n_states, fim_out);
    start_from_base(q_low_base, q_up_base, m, n_states, hybrid_out);
}

void destroy_uq_bands(UqBands *bands)
{
    if (bands == NULL)
    {
        return;
    }

    SUNMatDestroy(bands->q_low);
    SUNMatDestroy(bands->q_up);
    SUNMatDestroy(bands->cov_p);
    SUNMatDestroy(bands->std_y);
    *bands = (UqBands) {0};
}

int delta_method_bands(N_Vector parameters, N_Vector initial_condition, const sunrealtype t0, N_Vector times,
                       TransposedStates media_tot, ObservedData observed_data, const int *observed_idx, const int n_obs,
                       SUNMatrix loo_params, SUNMatrix q_low_base, SUNMatrix q_up_base, UqBands *fim_out,
                       UqBands *hybrid_out)
{
    const CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());
    const long n_states = conf->ode_expr.y_count;
    const int n_params = conf->ode_expr.p_count;
    const long m = NV_LENGTH_S(times);

    TransposedStates states = NULL;
    Sensitivities sensitivities = {0};

    // Before the first thing that can fail, so a caller always has bands to
    // write out even when no covariance can be built.
    conformal_only_bands(q_low_base, q_up_base, m, n_states, fim_out, hybrid_out);

    states = solve_ode(parameters, initial_condition, t0, times, &sensitivities);
    if (states == NULL)
    {
        fprintf(stderr, "ERROR: forward sensitivity solve failed\n");
        return 1;
    }
    SUNMatDestroy(states); // media_tot already holds the trajectory

    // Jacobian of the weighted residuals. Matlab flattens the m x n_obs block
    // column-major, so residual row i + m*j belongs to time i, observed state j.
    SUNMatrix jacobian = NewDenseMatrix(m * n_obs, n_params);
    double *weighted_residuals = malloc(m * n_obs * sizeof(double));

    for (int j = 0; j < n_obs; ++j)
    {
        const long state = observed_idx[j];
        const sunrealtype weight = cuqdyn_residual_weight(&conf->cost, j);

        for (long i = 0; i < m; ++i)
        {
            for (int p = 0; p < n_params; ++p)
            {
                SM_ELEMENT_D(jacobian, i + m * j, p) = sensitivity_at(sensitivities, state, i, p) * weight;
            }

            weighted_residuals[i + m * j] =
                    (SM_ELEMENT_D(media_tot, state, i) - SM_ELEMENT_D(observed_data, j, i)) * weight;
        }
    }

    const double sigma2 = cuqdyn_residual_variance(weighted_residuals, m * n_obs, n_params,
                                                   conf->cost.residual_model == RESIDUAL_MODEL_KNOWN_SIGMA &&
                                                           conf->cost.sigma_is_known);
    free(weighted_residuals);

    FimOptions options = fim_default_options();
    options.parameterization = conf->fim.parameterization == 1 ? FIM_PARAM_LOG : FIM_PARAM_NATURAL;
    options.relative_ridge = conf->fim.relative_ridge;
    options.rank_tol_factor = conf->fim.rank_tol_factor;
    options.weak_fraction_threshold = conf->fim.weak_fraction_threshold;

    FimResult *fim = cuqdyn_fim_covariance(jacobian, sigma2, parameters, options);
    SUNMatDestroy(jacobian);

    if (fim == NULL)
    {
        destroy_sensitivities(sensitivities);
        return 1;
    }

    fprintf(stdout, "FIM: rank %d/%d, condition number %.3e, ridge %.3e, sigma2 %.6g\n", fim->rank, n_params,
            fim->condition_number, fim->ridge, sigma2);

    /*
     * CUQDyn1_Plus propagates the FIM covariance; CUQDyn1_Plus_HybridCov keeps
     * its marginal scale but takes the correlation structure from the LOO
     * ensemble. Both are produced on every run: the sensitivities and the
     * conformal base are already in hand, so the second variety is one more
     * quadratic form, and the two can then be compared without a second fit.
     */
    const double z = gsl_cdf_ugaussian_Pinv(1.0 - conf->alp);

    fill_from_covariance(sensitivities, fim->cov_p, media_tot, observed_idx, n_obs, z, n_states, m, n_params, fim_out);

    SUNMatrix hybrid = cuqdyn_hybrid_covariance(fim->cov_p, loo_params);
    if (hybrid == NULL)
    {
        fprintf(stderr, "ERROR: could not build the hybrid covariance, its bands stay conformal-only\n");
        destroy_fim_result(fim);
        destroy_sensitivities(sensitivities);
        return 1;
    }

    fill_from_covariance(sensitivities, hybrid, media_tot, observed_idx, n_obs, z, n_states, m, n_params, hybrid_out);

    fprintf(stdout, "HybridCov: FIM marginal scale with LOO correlation\n");
    fprintf(stdout, "   marginal std devs  FIM:");
    for (int i = 0; i < n_params; ++i)
    {
        fprintf(stdout, " %.4g", sqrt(SM_ELEMENT_D(fim->cov_p, i, i)));
    }
    fprintf(stdout, "\n   marginal std devs  hybrid:");
    for (int i = 0; i < n_params; ++i)
    {
        fprintf(stdout, " %.4g", sqrt(SM_ELEMENT_D(hybrid, i, i)));
    }
    fprintf(stdout, "\n");

    SUNMatDestroy(hybrid);
    destroy_fim_result(fim);
    destroy_sensitivities(sensitivities);
    return 0;
}
