/*
 * Golden-vector comparison of the C kernels against the MATLAB reference.
 *
 * Inputs and expected outputs are produced by gen_golden.m. Only the
 * deterministic kernels are covered here: given identical inputs they must
 * produce identical outputs, so any difference is a transpilation error
 * rather than eSS noise. Running the whole pipeline end to end would compare
 * two independent stochastic optimisations and tell us very little.
 *
 *   ./test_golden [golden_dir] [rel_tolerance]
 *
 * Exit code is the number of failing comparisons, so it doubles as a ctest.
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "cuqdyn.h"
#include "fim.h"
#include "matlab.h"

static double g_rel_tol = 1e-9;
/* Per-case override. Cases whose linear algebra is inherently ill-conditioned
 * carry their own tolerance, justified in gen_golden.m. */
static double g_case_tol = 1e-9;
static int g_failures = 0;
static int g_checks = 0;

/* ------------------------------------------------------------------ io -- */

static SUNMatrix read_matrix(const char *dir, const char *file, int required)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", dir, file);

    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        if (required)
        {
            fprintf(stderr, "ERROR: cannot open %s\n", path);
            exit(2);
        }
        return NULL;
    }

    long rows, cols;
    if (fscanf(f, "%ld %ld", &rows, &cols) != 2)
    {
        fprintf(stderr, "ERROR: bad header in %s\n", path);
        exit(2);
    }

    SUNMatrix m = NewDenseMatrix(rows, cols);
    for (long i = 0; i < rows; ++i)
    {
        for (long j = 0; j < cols; ++j)
        {
            double v;
            if (fscanf(f, "%lf", &v) != 1)
            {
                fprintf(stderr, "ERROR: short read in %s at (%ld,%ld)\n", path, i, j);
                exit(2);
            }
            SM_ELEMENT_D(m, i, j) = v;
        }
    }
    fclose(f);
    return m;
}

/* Look up a key in a "key value" file. Returns 0 when the key is absent. */
static int read_kv(const char *dir, const char *file, const char *key, char *out, size_t out_len)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", dir, file);

    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        return 0;
    }

    char k[256], v[256];
    int found = 0;
    while (fscanf(f, "%255s %255s", k, v) == 2)
    {
        if (strcmp(k, key) == 0)
        {
            snprintf(out, out_len, "%s", v);
            found = 1;
            break;
        }
    }
    fclose(f);
    return found;
}

static double read_kv_double(const char *dir, const char *file, const char *key, double fallback)
{
    char buffer[256];
    if (!read_kv(dir, file, key, buffer, sizeof(buffer)))
    {
        return fallback;
    }
    if (strcmp(buffer, "inf") == 0 || strcmp(buffer, "Inf") == 0)
    {
        return INFINITY;
    }
    if (strcmp(buffer, "-inf") == 0 || strcmp(buffer, "-Inf") == 0)
    {
        return -INFINITY;
    }
    return atof(buffer);
}

/* ------------------------------------------------------------ compare -- */

static void report(const char *case_name, const char *what, double max_abs, double max_rel, int ok)
{
    g_checks++;
    if (!ok)
    {
        g_failures++;
    }
    printf("  %-22s %-20s max_abs=%.3e  max_rel=%.3e  %s\n", case_name, what, max_abs, max_rel,
           ok ? "ok" : "**FAIL**");
}

static void compare_matrix(const char *case_name, const char *what, SUNMatrix got, SUNMatrix expected)
{
    if (got == NULL || expected == NULL)
    {
        report(case_name, what, NAN, NAN, 0);
        return;
    }

    const long rows = SM_ROWS_D(expected);
    const long cols = SM_COLUMNS_D(expected);

    if (SM_ROWS_D(got) != rows || SM_COLUMNS_D(got) != cols)
    {
        printf("  %-22s %-20s shape %ldx%ld, expected %ldx%ld  **FAIL**\n", case_name, what, SM_ROWS_D(got),
               SM_COLUMNS_D(got), rows, cols);
        g_checks++;
        g_failures++;
        return;
    }

    /* Scale relative error by the largest expected magnitude: element-wise
     * ratios blow up on entries that are legitimately near zero. */
    double scale = 0.0;
    for (long i = 0; i < rows; ++i)
    {
        for (long j = 0; j < cols; ++j)
        {
            const double a = fabs(SM_ELEMENT_D(expected, i, j));
            if (a > scale)
            {
                scale = a;
            }
        }
    }
    if (scale == 0.0)
    {
        scale = 1.0;
    }

    double max_abs = 0.0;
    for (long i = 0; i < rows; ++i)
    {
        for (long j = 0; j < cols; ++j)
        {
            const double d = fabs(SM_ELEMENT_D(got, i, j) - SM_ELEMENT_D(expected, i, j));
            if (d > max_abs)
            {
                max_abs = d;
            }
        }
    }

    const double max_rel = max_abs / scale;
    report(case_name, what, max_abs, max_rel, max_rel <= g_case_tol);
}

static void compare_scalar(const char *case_name, const char *what, double got, double expected)
{
    if (isinf(expected) || isinf(got))
    {
        const int ok = (isinf(got) && isinf(expected) && (got > 0) == (expected > 0));
        printf("  %-22s %-20s got=%g expected=%g  %s\n", case_name, what, got, expected, ok ? "ok" : "**FAIL**");
        g_checks++;
        if (!ok)
        {
            g_failures++;
        }
        return;
    }

    const double max_abs = fabs(got - expected);
    const double scale = fabs(expected) > 1.0 ? fabs(expected) : 1.0;
    report(case_name, what, max_abs, max_abs / scale, max_abs / scale <= g_case_tol);
}

/* --------------------------------------------------------------- cases -- */

static void run_fim_case(const char *root, const char *name)
{
    char dir[1024];
    snprintf(dir, sizeof(dir), "%s/%s", root, name);
    g_case_tol = read_kv_double(dir, "expect_scalars.txt", "rel_tolerance", g_rel_tol);

    SUNMatrix j = read_matrix(dir, "J.txt", 1);
    SUNMatrix theta_m = read_matrix(dir, "theta.txt", 1);

    const long n_params = SM_ROWS_D(theta_m);
    N_Vector theta = New_Serial(n_params);
    for (long i = 0; i < n_params; ++i)
    {
        NV_Ith_S(theta, i) = SM_ELEMENT_D(theta_m, i, 0);
    }

    char buffer[256];
    FimOptions options = fim_default_options();

    options.parameterization = FIM_PARAM_LOG;
    if (read_kv(dir, "opts.txt", "parameterization", buffer, sizeof(buffer)) && strcmp(buffer, "natural") == 0)
    {
        options.parameterization = FIM_PARAM_NATURAL;
    }

    options.covariance_method = FIM_COV_RELATIVE_RIDGE;
    if (read_kv(dir, "opts.txt", "covariance_method", buffer, sizeof(buffer)) && strcmp(buffer, "svd_pinv") == 0)
    {
        options.covariance_method = FIM_COV_SVD_PINV;
    }

    options.relative_ridge = read_kv_double(dir, "opts.txt", "relative_ridge", 1e-12);
    options.rank_tol_factor = read_kv_double(dir, "opts.txt", "rank_tol_factor", 100.0);
    const double sigma2 = read_kv_double(dir, "opts.txt", "sigma2", 1.0);

    FimResult *result = cuqdyn_fim_covariance(j, sigma2, theta, options);
    if (result == NULL)
    {
        printf("  %-22s %-20s cuqdyn_fim_covariance returned NULL  **FAIL**\n", name, "(call)");
        g_checks++;
        g_failures++;
        SUNMatDestroy(j);
        SUNMatDestroy(theta_m);
        N_VDestroy(theta);
        return;
    }

    SUNMatrix expect_cov = read_matrix(dir, "expect_cov_p.txt", 1);
    compare_matrix(name, "cov_p", result->cov_p, expect_cov);
    SUNMatDestroy(expect_cov);

    SUNMatrix expect_log = read_matrix(dir, "expect_cov_log.txt", 0);
    if (expect_log != NULL)
    {
        compare_matrix(name, "cov_log", result->cov_log, expect_log);
        SUNMatDestroy(expect_log);
    }

    SUNMatrix expect_sv = read_matrix(dir, "expect_singular_values.txt", 1);
    SUNMatrix got_sv = NewDenseMatrix(NV_LENGTH_S(result->singular_values), 1);
    for (long i = 0; i < NV_LENGTH_S(result->singular_values); ++i)
    {
        SM_ELEMENT_D(got_sv, i, 0) = NV_Ith_S(result->singular_values, i);
    }
    compare_matrix(name, "singular_values", got_sv, expect_sv);
    SUNMatDestroy(got_sv);
    SUNMatDestroy(expect_sv);

    compare_scalar(name, "rank", (double) result->rank, read_kv_double(dir, "expect_scalars.txt", "rank", -1));
    compare_scalar(name, "n_weak", (double) result->n_weak,
                   read_kv_double(dir, "expect_scalars.txt", "n_weak_directions", -1));
    compare_scalar(name, "ridge", result->ridge, read_kv_double(dir, "expect_scalars.txt", "ridge", -1));
    compare_scalar(name, "condition_number", result->condition_number,
                   read_kv_double(dir, "expect_scalars.txt", "condition_number", -1));
    compare_scalar(name, "rank_tolerance", result->rank_tolerance,
                   read_kv_double(dir, "expect_scalars.txt", "rank_tolerance", -1));

    /* The MATLAB helper also returns max_weak_fraction / any_unreliable_bands
     * from local_reliability(). The C port never computes them, so there is
     * nothing to compare -- recorded here so the gap stays visible. */
    if (read_kv(dir, "expect_scalars.txt", "max_weak_fraction", buffer, sizeof(buffer)))
    {
        printf("  %-22s %-20s NOT IMPLEMENTED IN C (expected %s)\n", name, "max_weak_fraction", buffer);
    }

    destroy_fim_result(result);
    SUNMatDestroy(j);
    SUNMatDestroy(theta_m);
    N_VDestroy(theta);
}

static void run_hybrid_case(const char *root, const char *name)
{
    char dir[1024];
    snprintf(dir, sizeof(dir), "%s/%s", root, name);
    g_case_tol = read_kv_double(dir, "expect_scalars.txt", "rel_tolerance", g_rel_tol);

    SUNMatrix cov_fim = read_matrix(dir, "cov_fim.txt", 1);
    SUNMatrix loo = read_matrix(dir, "loo_params.txt", 1);
    SUNMatrix expected = read_matrix(dir, "expect_cov_hyb.txt", 1);

    SUNMatrix got = cuqdyn_hybrid_covariance(cov_fim, loo);
    compare_matrix(name, "cov_hyb", got, expected);

    if (got != NULL)
    {
        SUNMatDestroy(got);
    }
    SUNMatDestroy(cov_fim);
    SUNMatDestroy(loo);
    SUNMatDestroy(expected);
}

static void run_variance_case(const char *root, const char *name)
{
    char dir[1024];
    snprintf(dir, sizeof(dir), "%s/%s", root, name);
    g_case_tol = read_kv_double(dir, "expect_scalars.txt", "rel_tolerance", g_rel_tol);

    SUNMatrix residuals = read_matrix(dir, "residuals.txt", 1);
    const long n = SM_ROWS_D(residuals);

    char model[256] = "none";
    read_kv(dir, "opts.txt", "residual_model", model, sizeof(model));
    const int n_params = (int) read_kv_double(dir, "opts.txt", "n_params", 1);
    const int sigma_is_known = (int) read_kv_double(dir, "opts.txt", "sigma_is_known", 0);

    /* delta_bands.c passes exactly this conjunction. */
    const int known = (strcmp(model, "known_sigma") == 0) && sigma_is_known;

    double *values = malloc(n * sizeof(double));
    for (long i = 0; i < n; ++i)
    {
        values[i] = SM_ELEMENT_D(residuals, i, 0);
    }

    const double got = cuqdyn_residual_variance(values, n, n_params, known);
    compare_scalar(name, "sigma2", got, read_kv_double(dir, "expect_scalars.txt", "sigma2", -1));

    free(values);
    SUNMatDestroy(residuals);
}

static void run_quantile_case(const char *root, const char *name)
{
    char dir[1024], path[1024];
    snprintf(dir, sizeof(dir), "%s/%s", root, name);
    g_case_tol = g_rel_tol;

    snprintf(path, sizeof(path), "%s/cases.txt", dir);
    FILE *fin = fopen(path, "r");
    snprintf(path, sizeof(path), "%s/expect_quantiles.txt", dir);
    FILE *fexp = fopen(path, "r");

    if (fin == NULL || fexp == NULL)
    {
        fprintf(stderr, "ERROR: cannot open quantile case %s\n", dir);
        exit(2);
    }

    int n_vectors, n_probs;
    if (fscanf(fin, "%d %d", &n_vectors, &n_probs) != 2)
    {
        fprintf(stderr, "ERROR: bad quantile header\n");
        exit(2);
    }

    double *probs = malloc(n_probs * sizeof(double));
    for (int i = 0; i < n_probs; ++i)
    {
        if (fscanf(fin, "%lf", &probs[i]) != 1)
        {
            exit(2);
        }
    }

    double worst_abs = 0.0;
    int failures_here = 0;

    for (int v = 0; v < n_vectors; ++v)
    {
        int len;
        if (fscanf(fin, "%d", &len) != 1)
        {
            exit(2);
        }

        N_Vector vec = New_Serial(len);
        for (int i = 0; i < len; ++i)
        {
            double x;
            if (fscanf(fin, "%lf", &x) != 1)
            {
                exit(2);
            }
            NV_Ith_S(vec, i) = x;
        }

        for (int p = 0; p < n_probs; ++p)
        {
            double expected;
            if (fscanf(fexp, "%lf", &expected) != 1)
            {
                exit(2);
            }

            const double got = quantile(vec, probs[p]);
            const double d = fabs(got - expected);
            if (d > worst_abs)
            {
                worst_abs = d;
            }
            const double scale = fabs(expected) > 1.0 ? fabs(expected) : 1.0;
            if (d / scale > g_case_tol)
            {
                failures_here++;
                printf("      vector %d p=%g: got %.17g expected %.17g\n", v, probs[p], got, expected);
            }
        }

        N_VDestroy(vec);
    }

    g_checks++;
    if (failures_here > 0)
    {
        g_failures++;
    }
    printf("  %-22s %-20s max_abs=%.3e  %d/%d mismatched  %s\n", name, "quantile", worst_abs, failures_here,
           n_vectors * n_probs, failures_here == 0 ? "ok" : "**FAIL**");

    free(probs);
    fclose(fin);
    fclose(fexp);
}

/* ---------------------------------------------------------------- main -- */

int main(int argc, char *argv[])
{
    const char *root = argc > 1 ? argv[1] : "golden";
    if (argc > 2)
    {
        g_rel_tol = atof(argv[2]);
    }

    printf("Golden-vector validation: C kernels vs the MATLAB reference\n");
    printf("  golden dir: %s\n  rel tolerance: %.1e\n\n", root, g_rel_tol);

    char path[1024];
    snprintf(path, sizeof(path), "%s/MANIFEST.txt", root);
    FILE *manifest = fopen(path, "r");
    if (manifest == NULL)
    {
        fprintf(stderr, "ERROR: cannot open %s -- run gen_golden.m first\n", path);
        return 2;
    }

    char name[256];
    while (fscanf(manifest, "%255s", name) == 1)
    {
        if (strncmp(name, "fim_", 4) == 0)
        {
            run_fim_case(root, name);
        }
        else if (strncmp(name, "hyb_", 4) == 0)
        {
            run_hybrid_case(root, name);
        }
        else if (strncmp(name, "var_", 4) == 0)
        {
            run_variance_case(root, name);
        }
        else if (strncmp(name, "qnt_", 4) == 0)
        {
            run_quantile_case(root, name);
        }
        else
        {
            fprintf(stderr, "WARNING: unknown case prefix: %s\n", name);
        }
    }
    fclose(manifest);

    printf("\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures;
}
