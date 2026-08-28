/*
 * Layer 2.5: replay a recorded MATLAB eSS search through the C cost function.
 *
 * gen_cost_replay.m froze every parameter vector a seeded MATLAB MEIGO fit
 * evaluated, together with MATLAB's cost value J. This harness re-evaluates
 * the C cost at the SAME points - solve_ode (CVODES) + the weighted
 * sum-of-squares that obj_func computes, built from the same exported
 * library primitives - and compares J point by point.
 *
 * All the randomness lived on the MATLAB side; the frozen sequence makes the
 * comparison fully deterministic while covering exactly the region a real
 * search visits (bounds, stiff corners, wild intermediate points included).
 *
 *   ./test_cost_replay <evals.txt> <cuqdyn_config.xml> <data_file> [rel_tol]
 *
 * Exit code: number of points whose J disagrees beyond rel_tol (default
 * 1e-3; the two sides integrate with different correct solvers at rtol 1e-6,
 * so J agrees to ~1e-5 in practice - 1e-3 leaves margin without hiding real
 * bugs, which show up as orders of magnitude). 77 when evals.txt is absent,
 * so ctest reports SKIP.
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "cuqdyn.h"
#include "data_reader.h"
#include "functions.h"
#include "ode_solver.h"

int main(int argc, char *argv[])
{
    if (argc < 4)
    {
        fprintf(stderr, "Usage: %s <evals.txt> <cuqdyn_config.xml> <data_file> [rel_tol]\n", argv[0]);
        return 2;
    }
    const double rel_tol = argc > 4 ? atof(argv[4]) : 1e-3;

    FILE *f = fopen(argv[1], "r");
    if (f == NULL)
    {
        printf("No recorded evaluations at %s.\n", argv[1]);
        printf("Generate them with MATLAB first: cost_replay/gen_cost_replay.m\n");
        return 77; /* ctest SKIP_RETURN_CODE */
    }

    if (init_cuqdyn_context_from_file(argv[2]) == NULL)
    {
        fprintf(stderr, "ERROR: cannot read cuqdyn config %s\n", argv[2]);
        return 2;
    }
    const CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());

    CuqdynData data;
    if (read_data_file(argv[3], &data) != 0)
    {
        fprintf(stderr, "ERROR: cannot read data file %s\n", argv[3]);
        return 2;
    }

    long n_evals, n_params;
    if (fscanf(f, "%ld %ld", &n_evals, &n_params) != 2 || n_params != conf->ode_expr.p_count)
    {
        fprintf(stderr, "ERROR: bad header in %s (or p_count mismatch)\n", argv[1]);
        return 2;
    }

    const sunrealtype t0 = NV_Ith_S(data.times, 0);
    const long m = NV_LENGTH_S(data.times);
    N_Vector theta = New_Serial(n_params);

    long failures = 0;
    long solver_failures = 0;
    double max_rel = 0.0;
    double sum_rel = 0.0;
    long worst_idx = -1;

    for (long k = 0; k < n_evals; ++k)
    {
        double j_matlab;
        for (long p = 0; p < n_params; ++p)
        {
            if (fscanf(f, "%lf", &NV_Ith_S(theta, p)) != 1)
            {
                fprintf(stderr, "ERROR: short read at evaluation %ld\n", k);
                return 2;
            }
        }
        if (fscanf(f, "%lf", &j_matlab) != 1)
        {
            fprintf(stderr, "ERROR: short read (J) at evaluation %ld\n", k);
            return 2;
        }

        /* The C cost, assembled from the same primitives obj_func uses:
         * integrate every state, keep the observed rows, weight, square, sum. */
        TransposedStates states = solve_ode(theta, data.initial_values, t0, data.times);
        if (states == NULL)
        {
            /* MATLAB integrated this point and CVODES could not: that IS a
             * behavioural difference, counted separately. */
            solver_failures++;
            failures++;
            continue;
        }

        double j_c = 0.0;
        for (int j = 0; j < data.n_obs; ++j)
        {
            const long state = data.observed_idx[j];
            const double w = cuqdyn_residual_weight(&conf->cost, j);
            for (long i = 0; i < m; ++i)
            {
                const double r = (SM_ELEMENT_D(states, state, i) - SM_ELEMENT_D(data.observed_data, j, i)) * w;
                j_c += r * r;
            }
        }
        SUNMatDestroy(states);

        const double rel = fabs(j_c - j_matlab) / (fabs(j_matlab) > 1e-300 ? fabs(j_matlab) : 1.0);
        sum_rel += rel;
        if (rel > max_rel)
        {
            max_rel = rel;
            worst_idx = k;
        }
        if (rel > rel_tol)
        {
            if (failures < 5)
            {
                printf("  eval %-6ld J_matlab=%.10g  J_c=%.10g  rel=%.3e  **FAIL**\n", k, j_matlab, j_c, rel);
            }
            failures++;
        }
    }
    fclose(f);
    N_VDestroy(theta);

    printf("cost replay: %ld evaluations, %ld beyond rel_tol=%.1e (%ld CVODES failures)\n", n_evals, failures,
           rel_tol, solver_failures);
    printf("             mean rel=%.3e  max rel=%.3e (eval %ld)\n", sum_rel / (double) (n_evals > 0 ? n_evals : 1),
           max_rel, worst_idx);

    destroy_cuqdyn_data(&data);
    return failures > 0 ? (failures > 125 ? 125 : (int) failures) : 0;
}
