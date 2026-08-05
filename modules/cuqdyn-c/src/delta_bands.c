#include "uq_bands.h"

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
#include "sensitivity.h"

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

int delta_method_bands(N_Vector parameters, N_Vector initial_condition, const sunrealtype t0, N_Vector times,
                       TransposedStates media_tot, ObservedData observed_data, const int *observed_idx,
                       const int n_obs, SUNMatrix loo_params, SUNMatrix q_low, SUNMatrix q_up, SUNMatrix *cov_p_out,
                       SUNMatrix *std_y_out, SUNMatrix *q_low_alt_out, SUNMatrix *q_up_alt_out)
{
    const CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());
    const long n_states = conf->ode_expr.y_count;
    const int n_params = conf->ode_expr.p_count;
    const long m = NV_LENGTH_S(times);

    TransposedStates states = NULL;
    Sensitivities sensitivities = {0};

    if (solve_ode_with_sensitivities(parameters, initial_condition, t0, times, &states, &sensitivities) != 0)
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
     * ensemble. Everything downstream is identical.
     */
    SUNMatrix covariance = fim->cov_p;
    SUNMatrix hybrid = NULL;

    if (conf->uq_method == UQ_METHOD_HYBRIDCOV)
    {
        hybrid = cuqdyn_hybrid_covariance(fim->cov_p, loo_params);
        if (hybrid == NULL)
        {
            fprintf(stderr, "ERROR: could not build the hybrid covariance\n");
            destroy_fim_result(fim);
            destroy_sensitivities(sensitivities);
            return 1;
        }
        covariance = hybrid;

        fprintf(stdout, "HybridCov: FIM marginal scale with LOO correlation\n");
        fprintf(stdout, "   marginal std devs  FIM:");
        for (int i = 0; i < n_params; ++i)
        {
            fprintf(stdout, " %.4g", sqrt(SM_ELEMENT_D(fim->cov_p, i, i)));
        }
        fprintf(stdout, "\n   marginal std devs  hybrid:");
        for (int i = 0; i < n_params; ++i)
        {
            fprintf(stdout, " %.4g", sqrt(SM_ELEMENT_D(covariance, i, i)));
        }
        fprintf(stdout, "\n");
    }

    SUNMatrix std_y = propagate(sensitivities, covariance, n_states, m, n_params);

    const double z = gsl_cdf_ugaussian_Pinv(1.0 - conf->alp);

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

    /*
     * With the hybrid covariance, also propagate the plain FIM one so the two
     * bands can be drawn together. Only the hidden states differ: the observed
     * ones carry conformal bands either way.
     */
    *q_low_alt_out = NULL;
    *q_up_alt_out = NULL;

    if (hybrid != NULL)
    {
        SUNMatrix std_y_fim = propagate(sensitivities, fim->cov_p, n_states, m, n_params);

        // SM_ELEMENT_D does not parenthesise its argument, so the matrices are
        // held in locals rather than dereferenced inside the macro.
        SUNMatrix q_low_fim = NewDenseMatrix(m, n_states);
        SUNMatrix q_up_fim = NewDenseMatrix(m, n_states);
        SUNMatCopy(q_low, q_low_fim);
        SUNMatCopy(q_up, q_up_fim);

        for (long k = 0; k < n_states; ++k)
        {
            if (is_observed(observed_idx, n_obs, k))
            {
                continue;
            }

            for (long i = 1; i < m; ++i)
            {
                const double centre = SM_ELEMENT_D(media_tot, k, i);
                const double half_width = z * SM_ELEMENT_D(std_y_fim, k, i);
                SM_ELEMENT_D(q_low_fim, i, k) = centre - half_width;
                SM_ELEMENT_D(q_up_fim, i, k) = centre + half_width;
            }
        }

        SUNMatDestroy(std_y_fim);
        *q_low_alt_out = q_low_fim;
        *q_up_alt_out = q_up_fim;
    }

    *cov_p_out = NewDenseMatrix(n_params, n_params);
    SUNMatCopy(covariance, *cov_p_out);
    *std_y_out = std_y;

    if (hybrid != NULL)
    {
        SUNMatDestroy(hybrid);
    }
    destroy_fim_result(fim);
    destroy_sensitivities(sensitivities);
    return 0;
}
