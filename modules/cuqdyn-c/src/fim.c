#include "fim.h"

#include <float.h>
#include <gsl/gsl_eigen.h>
#include <gsl/gsl_linalg.h>
#include <gsl/gsl_matrix.h>
#include <gsl/gsl_vector.h>
#include <math.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "cuqdyn.h"

FimOptions fim_default_options()
{
    FimOptions options;
    options.parameterization = FIM_PARAM_LOG;
    options.covariance_method = FIM_COV_RELATIVE_RIDGE;
    options.relative_ridge = 1e-12;
    options.rank_tol_factor = 100.0;
    options.weak_fraction_threshold = 0.1;
    return options;
}

double cuqdyn_residual_variance(const double *weighted_residuals, const long n_residuals, const int n_params,
                                const int sigma_is_known)
{
    if (sigma_is_known)
    {
        return 1.0;
    }

    double sum_of_squares = 0.0;
    for (long i = 0; i < n_residuals; ++i)
    {
        sum_of_squares += weighted_residuals[i] * weighted_residuals[i];
    }

    const long dof = n_residuals - n_params;
    return sum_of_squares / (double) (dof > 1 ? dof : 1);
}

/// Matlab's eps(x): the distance from x to the next larger double.
static double matlab_eps(const double x) { return nextafter(x, INFINITY) - x; }

void destroy_fim_result(FimResult *result)
{
    if (result == NULL)
    {
        return;
    }

    SUNMatDestroy(result->cov_p);
    SUNMatDestroy(result->cov_log);
    SUNMatDestroy(result->v);
    N_VDestroy(result->singular_values);

    free(result);
}

FimResult *cuqdyn_fim_covariance(SUNMatrix j_nat, const double sigma2, N_Vector theta, const FimOptions options)
{
    if (j_nat == NULL || theta == NULL)
    {
        fprintf(stderr, "ERROR: NULL argument in cuqdyn_fim_covariance()\n");
        return NULL;
    }

    const long n_residuals = SM_ROWS_D(j_nat);
    const long n_params = SM_COLUMNS_D(j_nat);

    if (n_params != NV_LENGTH_S(theta))
    {
        fprintf(stderr, "ERROR: Jacobian has %ld columns but theta has %ld entries\n", n_params, NV_LENGTH_S(theta));
        return NULL;
    }

    // The Golub-Reinsch SVD in GSL requires at least as many rows as columns.
    if (n_residuals < n_params)
    {
        fprintf(stderr, "ERROR: FIM needs at least as many residuals (%ld) as parameters (%ld)\n", n_residuals,
                n_params);
        return NULL;
    }

    // Fall back to natural parameters when the log transform is undefined,
    // mirroring the warning path in cuqdyn_fim_covariance.m.
    int use_log = options.parameterization == FIM_PARAM_LOG;
    if (use_log)
    {
        for (long i = 0; i < n_params; ++i)
        {
            if (NV_Ith_S(theta, i) <= 0.0)
            {
                fprintf(stderr, "WARNING: Non-positive parameters found; falling back to natural-parameter FIM.\n");
                use_log = 0;
                break;
            }
        }
    }

    // J_fim = J_nat * diag(theta) in the log parameterization, J_nat otherwise.
    gsl_matrix *j_fim = gsl_matrix_alloc(n_residuals, n_params);
    for (long i = 0; i < n_residuals; ++i)
    {
        for (long j = 0; j < n_params; ++j)
        {
            const double scale = use_log ? NV_Ith_S(theta, j) : 1.0;
            gsl_matrix_set(j_fim, i, j, SM_ELEMENT_D(j_nat, i, j) * scale);
        }
    }

    // A = J_fim' * J_fim, formed before the SVD destroys the working copy.
    gsl_matrix *a = gsl_matrix_alloc(n_params, n_params);
    for (long i = 0; i < n_params; ++i)
    {
        for (long j = 0; j < n_params; ++j)
        {
            double acc = 0.0;
            for (long k = 0; k < n_residuals; ++k)
            {
                acc += gsl_matrix_get(j_fim, k, i) * gsl_matrix_get(j_fim, k, j);
            }
            gsl_matrix_set(a, i, j, acc);
        }
    }

    gsl_matrix *v = gsl_matrix_alloc(n_params, n_params);
    gsl_vector *s = gsl_vector_alloc(n_params);
    gsl_vector *work = gsl_vector_alloc(n_params);

    if (gsl_linalg_SV_decomp(j_fim, v, s, work) != 0)
    {
        fprintf(stderr, "ERROR: SVD of the residual Jacobian failed\n");
        gsl_vector_free(work);
        gsl_vector_free(s);
        gsl_matrix_free(v);
        gsl_matrix_free(a);
        gsl_matrix_free(j_fim);
        return NULL;
    }
    gsl_vector_free(work);

    double smax = 0.0;
    for (long i = 0; i < n_params; ++i)
    {
        const double value = gsl_vector_get(s, i);
        if (value > smax)
        {
            smax = value;
        }
    }

    const long max_dim = n_residuals > n_params ? n_residuals : n_params;
    const double rank_tolerance = options.rank_tol_factor * (double) max_dim * matlab_eps(smax > 1.0 ? smax : 1.0);

    int rank = 0;
    double smin_kept = INFINITY;
    for (long i = 0; i < n_params; ++i)
    {
        const double value = gsl_vector_get(s, i);
        if (value > rank_tolerance)
        {
            rank++;
            if (value < smin_kept)
            {
                smin_kept = value;
            }
        }
    }

    double ridge = 0.0;
    gsl_matrix *cov_fim = gsl_matrix_alloc(n_params, n_params);

    if (options.covariance_method == FIM_COV_RELATIVE_RIDGE)
    {
        const double smax_squared = smax * smax;
        ridge = options.relative_ridge * (smax_squared > 1.0 ? smax_squared : 1.0);

        // Cov = sigma2 * inv(J'J + ridge * I). The matrix is symmetric positive
        // definite once the ridge is applied, so a Cholesky inverse is enough.
        gsl_matrix *regularized = gsl_matrix_alloc(n_params, n_params);
        gsl_matrix_memcpy(regularized, a);
        for (long i = 0; i < n_params; ++i)
        {
            gsl_matrix_set(regularized, i, i, gsl_matrix_get(regularized, i, i) + ridge);
        }

        gsl_error_handler_t *previous_handler = gsl_set_error_handler_off();
        int status = gsl_linalg_cholesky_decomp1(regularized);
        if (status == 0)
        {
            status = gsl_linalg_cholesky_invert(regularized);
        }
        gsl_set_error_handler(previous_handler);

        if (status != 0)
        {
            fprintf(stderr, "ERROR: Could not invert the regularized FIM\n");
            gsl_matrix_free(regularized);
            gsl_matrix_free(cov_fim);
            gsl_vector_free(s);
            gsl_matrix_free(v);
            gsl_matrix_free(a);
            gsl_matrix_free(j_fim);
            return NULL;
        }

        for (long i = 0; i < n_params; ++i)
        {
            for (long j = 0; j < n_params; ++j)
            {
                gsl_matrix_set(cov_fim, i, j, sigma2 * gsl_matrix_get(regularized, i, j));
            }
        }
        gsl_matrix_free(regularized);
    }
    else
    {
        // Truncated pseudo-inverse: Cov = sigma2 * Vk * diag(1/s_k^2) * Vk'.
        if (rank < n_params)
        {
            fprintf(stderr, "WARNING: SVD pseudoinverse drops %ld weak FIM direction(s); "
                            "propagated uncertainty can be anti-conservative.\n",
                    n_params - rank);
        }

        gsl_matrix_set_zero(cov_fim);
        for (long i = 0; i < n_params; ++i)
        {
            for (long j = 0; j < n_params; ++j)
            {
                double acc = 0.0;
                for (long k = 0; k < n_params; ++k)
                {
                    const double sk = gsl_vector_get(s, k);
                    if (sk > rank_tolerance)
                    {
                        acc += gsl_matrix_get(v, i, k) * gsl_matrix_get(v, j, k) / (sk * sk);
                    }
                }
                gsl_matrix_set(cov_fim, i, j, sigma2 * acc);
            }
        }
    }

    // Symmetrize, then map back to natural units when working in log space.
    FimResult *result = malloc(sizeof(FimResult));
    result->cov_p = NewDenseMatrix(n_params, n_params);
    result->cov_log = use_log ? NewDenseMatrix(n_params, n_params) : NULL;
    result->v = NewDenseMatrix(n_params, n_params);
    result->singular_values = New_Serial(n_params);

    for (long i = 0; i < n_params; ++i)
    {
        for (long j = 0; j < n_params; ++j)
        {
            const double symmetric = (gsl_matrix_get(cov_fim, i, j) + gsl_matrix_get(cov_fim, j, i)) / 2.0;

            if (use_log)
            {
                SM_ELEMENT_D(result->cov_log, i, j) = symmetric;
                SM_ELEMENT_D(result->cov_p, i, j) = NV_Ith_S(theta, i) * symmetric * NV_Ith_S(theta, j);
            }
            else
            {
                SM_ELEMENT_D(result->cov_p, i, j) = symmetric;
            }

            SM_ELEMENT_D(result->v, i, j) = gsl_matrix_get(v, i, j);
        }
    }

    // The natural-unit covariance is symmetrized once more, as in the Matlab.
    for (long i = 0; i < n_params; ++i)
    {
        for (long j = i + 1; j < n_params; ++j)
        {
            const double symmetric = (SM_ELEMENT_D(result->cov_p, i, j) + SM_ELEMENT_D(result->cov_p, j, i)) / 2.0;
            SM_ELEMENT_D(result->cov_p, i, j) = symmetric;
            SM_ELEMENT_D(result->cov_p, j, i) = symmetric;
        }
    }

    for (long i = 0; i < n_params; ++i)
    {
        NV_Ith_S(result->singular_values, i) = gsl_vector_get(s, i);
    }

    result->rank = rank;
    result->n_weak = (int) n_params - rank;
    result->ridge = ridge;
    result->sigma2 = sigma2;
    result->rank_tolerance = rank_tolerance;
    result->parameterization = use_log ? FIM_PARAM_LOG : FIM_PARAM_NATURAL;
    result->condition_number = (rank == 0 || smax == 0.0 || rank < n_params) ? INFINITY : smax / smin_kept;

    gsl_matrix_free(cov_fim);
    gsl_vector_free(s);
    gsl_matrix_free(v);
    gsl_matrix_free(a);
    gsl_matrix_free(j_fim);

    return result;
}

SUNMatrix cuqdyn_hybrid_covariance(SUNMatrix cov_fim, SUNMatrix loo_params)
{
    if (cov_fim == NULL || loo_params == NULL)
    {
        fprintf(stderr, "ERROR: NULL argument in cuqdyn_hybrid_covariance()\n");
        return NULL;
    }

    const long n_params = SM_COLUMNS_D(cov_fim);
    const long n_samples = SM_ROWS_D(loo_params);

    if (SM_COLUMNS_D(loo_params) != n_params)
    {
        fprintf(stderr, "ERROR: loo_params has %ld columns but the covariance is %ld x %ld\n",
                SM_COLUMNS_D(loo_params), n_params, n_params);
        return NULL;
    }

    if (n_samples < 2)
    {
        fprintf(stderr, "ERROR: the LOO correlation needs at least two refits, got %ld\n", n_samples);
        return NULL;
    }

    // Sample covariance of the LOO parameter ensemble, normalised by n - 1.
    gsl_matrix *cov_loo = gsl_matrix_alloc(n_params, n_params);
    double *means = calloc(n_params, sizeof(double));

    for (long j = 0; j < n_params; ++j)
    {
        for (long k = 0; k < n_samples; ++k)
        {
            means[j] += SM_ELEMENT_D(loo_params, k, j);
        }
        means[j] /= (double) n_samples;
    }

    for (long i = 0; i < n_params; ++i)
    {
        for (long j = 0; j < n_params; ++j)
        {
            double acc = 0.0;
            for (long k = 0; k < n_samples; ++k)
            {
                acc += (SM_ELEMENT_D(loo_params, k, i) - means[i]) * (SM_ELEMENT_D(loo_params, k, j) - means[j]);
            }
            // The tiny diagonal bump keeps a parameter that never moved from
            // making the correlation undefined.
            gsl_matrix_set(cov_loo, i, j, acc / (double) (n_samples - 1) + (i == j ? 1e-14 : 0.0));
        }
    }
    free(means);

    // Correlation matrix of the ensemble.
    double *inverse_std = malloc(n_params * sizeof(double));
    for (long i = 0; i < n_params; ++i)
    {
        const double std = sqrt(gsl_matrix_get(cov_loo, i, i));
        inverse_std[i] = std < 1e-15 ? 0.0 : 1.0 / std;
    }

    gsl_matrix *correlation = gsl_matrix_alloc(n_params, n_params);
    for (long i = 0; i < n_params; ++i)
    {
        for (long j = 0; j < n_params; ++j)
        {
            double value = inverse_std[i] * gsl_matrix_get(cov_loo, i, j) * inverse_std[j];
            value = value > 1.0 ? 1.0 : (value < -1.0 ? -1.0 : value);
            gsl_matrix_set(correlation, i, j, value);
        }
    }
    free(inverse_std);

    for (long i = 0; i < n_params; ++i)
    {
        for (long j = i + 1; j < n_params; ++j)
        {
            const double symmetric = (gsl_matrix_get(correlation, i, j) + gsl_matrix_get(correlation, j, i)) / 2.0;
            gsl_matrix_set(correlation, i, j, symmetric);
            gsl_matrix_set(correlation, j, i, symmetric);
        }
        gsl_matrix_set(correlation, i, i, 1.0);
    }

    // Cov_hyb = diag(D_fim) * R_loo * diag(D_fim)
    gsl_matrix *hybrid = gsl_matrix_alloc(n_params, n_params);
    double *fim_std = malloc(n_params * sizeof(double));
    for (long i = 0; i < n_params; ++i)
    {
        const double variance = SM_ELEMENT_D(cov_fim, i, i);
        fim_std[i] = sqrt(variance > 0.0 ? variance : 0.0);
    }

    for (long i = 0; i < n_params; ++i)
    {
        for (long j = 0; j < n_params; ++j)
        {
            gsl_matrix_set(hybrid, i, j, fim_std[i] * gsl_matrix_get(correlation, i, j) * fim_std[j]);
        }
    }

    // Scaling a correlation matrix keeps it positive semi-definite in exact
    // arithmetic; clamp any negative eigenvalue that rounding introduces.
    gsl_matrix *vectors = gsl_matrix_alloc(n_params, n_params);
    gsl_vector *values = gsl_vector_alloc(n_params);
    gsl_matrix *work_copy = gsl_matrix_alloc(n_params, n_params);
    gsl_matrix_memcpy(work_copy, hybrid);

    gsl_eigen_symmv_workspace *workspace = gsl_eigen_symmv_alloc(n_params);
    gsl_error_handler_t *previous_handler = gsl_set_error_handler_off();
    const int status = gsl_eigen_symmv(work_copy, values, vectors, workspace);
    gsl_set_error_handler(previous_handler);
    gsl_eigen_symmv_free(workspace);
    gsl_matrix_free(work_copy);

    long negative = 0;
    if (status == 0)
    {
        for (long i = 0; i < n_params; ++i)
        {
            if (gsl_vector_get(values, i) < 0.0)
            {
                gsl_vector_set(values, i, 0.0);
                negative++;
            }
        }

        if (negative > 0)
        {
            fprintf(stderr, "WARNING: %ld negative eigenvalue(s) in the hybrid covariance; clamped to 0\n", negative);
            for (long i = 0; i < n_params; ++i)
            {
                for (long j = 0; j < n_params; ++j)
                {
                    double acc = 0.0;
                    for (long k = 0; k < n_params; ++k)
                    {
                        acc += gsl_matrix_get(vectors, i, k) * gsl_vector_get(values, k) * gsl_matrix_get(vectors, j, k);
                    }
                    gsl_matrix_set(hybrid, i, j, acc);
                }
            }
        }
    }

    SUNMatrix result = NewDenseMatrix(n_params, n_params);
    for (long i = 0; i < n_params; ++i)
    {
        for (long j = 0; j < n_params; ++j)
        {
            SM_ELEMENT_D(result, i, j) = (gsl_matrix_get(hybrid, i, j) + gsl_matrix_get(hybrid, j, i)) / 2.0;
        }
    }

    gsl_vector_free(values);
    gsl_matrix_free(vectors);
    gsl_matrix_free(hybrid);
    gsl_matrix_free(correlation);
    gsl_matrix_free(cov_loo);

    return result;
}
