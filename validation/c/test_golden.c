/*
 * Golden-vector comparison of the C kernels against the MATLAB reference.
 *
 * Inputs and expected outputs are produced by gen_golden.m into one file,
 * references/golden.txt: a [manifest] section listing the cases and, per
 * case, one section per array or key-value set, named [<case>/<array>]. Only
 * the deterministic kernels are covered here: given identical inputs they must
 * produce identical outputs, so any difference is a transpilation error
 * rather than eSS noise. Running the whole pipeline end to end would compare
 * two independent stochastic optimisations and tell us very little.
 *
 *   ./test_golden [golden_file] [rel_tolerance]
 *
 * Exit code is the number of failing comparisons, so it doubles as a ctest.
 */

#include <math.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "cuqdyn.h"
#include "fim.h"
#include "matlab.h"
#include "refio.h"
#include "textio.h"

static double g_rel_tol = 1e-9;
/* Per-case override. Cases whose linear algebra is inherently ill-conditioned
 * carry their own tolerance, justified in gen_golden.m. */
static double g_case_tol = 1e-9;
static int g_failures = 0;
static int g_checks = 0;

/* ------------------------------------------------------------------ io -- */

/* The golden file, set once in main; every case reads its sections from it. */
static const char *g_golden = "golden.txt";

/* "<case>/<array>", the section name of one array of one case. */
static const char *section_name(char *buf, size_t n, const char *case_name, const char *array)
{
    snprintf(buf, n, "%s/%s", case_name, array);
    return buf;
}

/* Opens the section of one array of one case (see refio.h). */
static FILE *open_case_section(const char *case_name, const char *array, int required)
{
    char section[512];
    return open_section(g_golden, section_name(section, sizeof(section), case_name, array), required);
}

static SUNMatrix read_matrix(const char *case_name, const char *array, int required)
{
    FILE *f = open_case_section(case_name, array, required);
    if (f == NULL)
    {
        return NULL;
    }

    long rows, cols;
    if (!read_long(f, &rows) || !read_long(f, &cols) || rows < 0 || cols < 0)
    {
        fprintf(stderr, "ERROR: bad header in [%s/%s]\n", case_name, array);
        exit(2);
    }

    SUNMatrix m = NewDenseMatrix(rows, cols);
    for (long i = 0; i < rows; ++i)
    {
        for (long j = 0; j < cols; ++j)
        {
            double v;
            if (!read_double(f, &v))
            {
                fprintf(stderr, "ERROR: short read in [%s/%s] at (%ld,%ld)\n", case_name, array, i, j);
                exit(2);
            }
            SM_ELEMENT_D(m, i, j) = v;
        }
    }
    fclose(f);
    return m;
}

/* Look up a key in a "key value" section of a case. Returns 0 when absent. */
static int read_kv(const char *case_name, const char *array, const char *key, char *out, size_t out_len)
{
    char section[512];
    return lookup_kv(g_golden, section_name(section, sizeof(section), case_name, array), key, out, out_len);
}

static double read_kv_double(const char *case_name, const char *array, const char *key, double fallback)
{
    char buffer[256];
    if (!read_kv(case_name, array, key, buffer, sizeof(buffer)))
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
    double v;
    if (!parse_double(buffer, &v))
    {
        fprintf(stderr, "ERROR: [%s/%s]: %s is not a number: %s\n", case_name, array, key, buffer);
        exit(2);
    }
    return v;
}

/* ------------------------------------------------------------ compare -- */

static void report(const char *case_name, const char *what, double max_abs, double max_rel, int ok)
{
    g_checks++;
    if (!ok)
    {
        g_failures++;
    }
    printf("  %-22s %-20s max_abs=%.3e  max_rel=%.3e  %s\n", case_name, what, max_abs, max_rel, ok ? "ok" : "**FAIL**");
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

static void run_fim_case(const char *name)
{
    g_case_tol = read_kv_double(name, "expect_scalars", "rel_tolerance", g_rel_tol);

    SUNMatrix j = read_matrix(name, "J", 1);
    SUNMatrix theta_m = read_matrix(name, "theta", 1);

    const long n_params = SM_ROWS_D(theta_m);
    N_Vector theta = New_Serial(n_params);
    for (long i = 0; i < n_params; ++i)
    {
        NV_Ith_S(theta, i) = SM_ELEMENT_D(theta_m, i, 0);
    }

    char buffer[256];
    FimOptions options = fim_default_options();

    options.parameterization = FIM_PARAM_LOG;
    if (read_kv(name, "opts", "parameterization", buffer, sizeof(buffer)) && strcmp(buffer, "natural") == 0)
    {
        options.parameterization = FIM_PARAM_NATURAL;
    }

    options.covariance_method = FIM_COV_RELATIVE_RIDGE;
    if (read_kv(name, "opts", "covariance_method", buffer, sizeof(buffer)) && strcmp(buffer, "svd_pinv") == 0)
    {
        options.covariance_method = FIM_COV_SVD_PINV;
    }

    options.relative_ridge = read_kv_double(name, "opts", "relative_ridge", 1e-12);
    options.rank_tol_factor = read_kv_double(name, "opts", "rank_tol_factor", 100.0);
    const double sigma2 = read_kv_double(name, "opts", "sigma2", 1.0);

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

    SUNMatrix expect_cov = read_matrix(name, "expect_cov_p", 1);
    compare_matrix(name, "cov_p", result->cov_p, expect_cov);
    SUNMatDestroy(expect_cov);

    SUNMatrix expect_log = read_matrix(name, "expect_cov_log", 0);
    if (expect_log != NULL)
    {
        compare_matrix(name, "cov_log", result->cov_log, expect_log);
        SUNMatDestroy(expect_log);
    }

    SUNMatrix expect_sv = read_matrix(name, "expect_singular_values", 1);
    SUNMatrix got_sv = NewDenseMatrix(NV_LENGTH_S(result->singular_values), 1);
    for (long i = 0; i < NV_LENGTH_S(result->singular_values); ++i)
    {
        SM_ELEMENT_D(got_sv, i, 0) = NV_Ith_S(result->singular_values, i);
    }
    compare_matrix(name, "singular_values", got_sv, expect_sv);
    SUNMatDestroy(got_sv);
    SUNMatDestroy(expect_sv);

    compare_scalar(name, "rank", (double) result->rank, read_kv_double(name, "expect_scalars", "rank", -1));
    compare_scalar(name, "n_weak", (double) result->n_weak,
                   read_kv_double(name, "expect_scalars", "n_weak_directions", -1));
    compare_scalar(name, "ridge", result->ridge, read_kv_double(name, "expect_scalars", "ridge", -1));
    compare_scalar(name, "condition_number", result->condition_number,
                   read_kv_double(name, "expect_scalars", "condition_number", -1));
    compare_scalar(name, "rank_tolerance", result->rank_tolerance,
                   read_kv_double(name, "expect_scalars", "rank_tolerance", -1));

    /* The MATLAB helper also returns max_weak_fraction / any_unreliable_bands
     * from local_reliability(). The C port never computes them, so there is
     * nothing to compare -- recorded here so the gap stays visible. */
    if (read_kv(name, "expect_scalars", "max_weak_fraction", buffer, sizeof(buffer)))
    {
        printf("  %-22s %-20s NOT IMPLEMENTED IN C (expected %s)\n", name, "max_weak_fraction", buffer);
    }

    destroy_fim_result(result);
    SUNMatDestroy(j);
    SUNMatDestroy(theta_m);
    N_VDestroy(theta);
}

static void run_hybrid_case(const char *name)
{
    g_case_tol = read_kv_double(name, "expect_scalars", "rel_tolerance", g_rel_tol);

    SUNMatrix cov_fim = read_matrix(name, "cov_fim", 1);
    SUNMatrix loo = read_matrix(name, "loo_params", 1);
    SUNMatrix expected = read_matrix(name, "expect_cov_hyb", 1);

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

static void run_variance_case(const char *name)
{
    g_case_tol = read_kv_double(name, "expect_scalars", "rel_tolerance", g_rel_tol);

    SUNMatrix residuals = read_matrix(name, "residuals", 1);
    const long n = SM_ROWS_D(residuals);

    char model[256] = "none";
    read_kv(name, "opts", "residual_model", model, sizeof(model));
    const int n_params = (int) read_kv_double(name, "opts", "n_params", 1);
    const int sigma_is_known = (int) read_kv_double(name, "opts", "sigma_is_known", 0);

    /* delta_bands.c passes exactly this conjunction. */
    const int known = (strcmp(model, "known_sigma") == 0) && sigma_is_known;

    double *values = malloc(n * sizeof(double));
    for (long i = 0; i < n; ++i)
    {
        values[i] = SM_ELEMENT_D(residuals, i, 0);
    }

    const double got = cuqdyn_residual_variance(values, n, n_params, known);
    compare_scalar(name, "sigma2", got, read_kv_double(name, "expect_scalars", "sigma2", -1));

    free(values);
    SUNMatDestroy(residuals);
}

static void run_quantile_case(const char *name)
{
    g_case_tol = g_rel_tol;

    FILE *fin = open_case_section(name, "cases", 1);
    FILE *fexp = open_case_section(name, "expect_quantiles", 1);

    int n_vectors, n_probs;
    if (!read_int(fin, &n_vectors) || !read_int(fin, &n_probs) || n_vectors < 0 || n_probs < 1 || n_probs > 4096)
    {
        fprintf(stderr, "ERROR: bad quantile header\n");
        exit(2);
    }

    double probs[4096]; /* n_probs is bounded by the header check above */
    for (int i = 0; i < n_probs; ++i)
    {
        if (!read_double(fin, &probs[i]))
        {
            exit(2);
        }
    }

    double worst_abs = 0.0;
    int failures_here = 0;

    for (int v = 0; v < n_vectors; ++v)
    {
        int len;
        if (!read_int(fin, &len) || len < 0)
        {
            exit(2);
        }

        N_Vector vec = New_Serial(len);
        for (int i = 0; i < len; ++i)
        {
            double x;
            if (!read_double(fin, &x))
            {
                exit(2);
            }
            NV_Ith_S(vec, i) = x;
        }

        for (int p = 0; p < n_probs; ++p)
        {
            double expected;
            if (!read_double(fexp, &expected))
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

    fclose(fin);
    fclose(fexp);
}

/* ---------------------------------------------------------------- main -- */

int main(int argc, char *argv[])
{
    if (argc > 1)
    {
        g_golden = argv[1];
    }
    if (argc > 2 && !parse_double(argv[2], &g_rel_tol))
    {
        fprintf(stderr, "ERROR: rel tolerance is not a number: %s\n", argv[2]);
        return 2;
    }

    printf("Golden-vector validation: C kernels vs the MATLAB reference\n");
    printf("  golden file: %s\n  rel tolerance: %.1e\n\n", g_golden, g_rel_tol);

    FILE *manifest = open_section(g_golden, "manifest", 0);
    if (manifest == NULL)
    {
        fprintf(stderr, "ERROR: cannot read [manifest] from %s -- run gen_golden.m first\n", g_golden);
        return 2;
    }

    char name[256];
    while (read_name(manifest, name, sizeof(name)))
    {
        if (strncmp(name, "fim_", 4) == 0)
        {
            run_fim_case(name);
        }
        else if (strncmp(name, "hyb_", 4) == 0)
        {
            run_hybrid_case(name);
        }
        else if (strncmp(name, "var_", 4) == 0)
        {
            run_variance_case(name);
        }
        else if (strncmp(name, "qnt_", 4) == 0)
        {
            run_quantile_case(name);
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
