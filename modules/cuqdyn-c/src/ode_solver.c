#include <config.h>
#include <cvodes/cvodes.h>
#include <functions.h>
#include <ode_solver.h>
#include <stdlib.h>
#include <string.h>
#include <sunlinsol/sunlinsol_dense.h>
#include <sunmatrix/sunmatrix_dense.h>
#include <sunmatrix/sunmatrix_sparse.h>

#include "cuqdyn.h"
#include "cvodes/cvodes_ls.h"
#include "sundials/sundials_types.h"

static int check_retval(void *, const char *, int);


/*
 * Solves the ODE at the given parameters.
 *
 * Every allocation is released on every path. This matters more than it looks:
 * solve_ode runs once per objective evaluation, so a single leaked dense matrix
 * per call is millions of them over a full run, which is enough to exhaust
 * memory on the larger models.
 */
TransposedStates solve_ode(N_Vector parameters, N_Vector initial_values, sunrealtype t0, N_Vector times)
{
    CuqdynConf *cuqdyn_conf = get_cuqdyn_conf(get_cuqdyn_context());
    Tolerances tolerances = cuqdyn_conf->tolerances;

    int retval;
    void *cvode_mem = NULL;
    SUNMatrix A = NULL;
    SUNLinearSolver LS = NULL;
    N_Vector yout = NULL;
    N_Vector cloned_abs_tol = NULL;
    TransposedStates result = NULL;
    int failed = 1;

    cvode_mem = CVodeCreate(CV_BDF, get_sundials_ctx());
    if (check_retval((void *) cvode_mem, "CVodeCreate", 0))
    {
        goto cleanup;
    }

    retval = CVodeInit(cvode_mem, ode_model_fun, t0, initial_values);
    if (check_retval(&retval, "CVodeInit", 1))
    {
        goto cleanup;
    }

    cloned_abs_tol = New_Serial(tolerances.atol_len);
    memcpy(NV_DATA_S(cloned_abs_tol), tolerances.atol, tolerances.atol_len * sizeof(sunrealtype));

    // We clone the tolerances because the CVodeFree function frees the memory allocated for the abs_tol it receives
    retval = CVodeSVtolerances(cvode_mem, tolerances.rtol, cloned_abs_tol);
    if (check_retval(&retval, "CVodeSVtolerances", 1))
    {
        goto cleanup;
    }

    retval = CVodeSetUserData(cvode_mem, parameters);
    if (check_retval(&retval, "CVodeSetUserData", 1))
    {
        goto cleanup;
    }

    A = NewDenseMatrix(cuqdyn_conf->ode_expr.y_count, cuqdyn_conf->ode_expr.y_count);
    LS = SUNLinSol_Dense(initial_values, A, get_sundials_ctx());
    retval = CVodeSetLinearSolver(cvode_mem, LS, A);
    if (check_retval(&retval, "CVodeSetLinearSolver", 1))
    {
        goto cleanup;
    }

    char *min_step_s = getenv("CUQDYN_CVODES_MIN_STEP");
    if (min_step_s != NULL)
    {
        sunrealtype min_step = atof(min_step_s);
        retval = CVodeSetMinStep(cvode_mem, min_step);
        if (check_retval(&retval, "CVodeSetMinStep", 1))
        {
            goto cleanup;
        }
    }

    char *max_num_steps_s = getenv("CUQDYN_CVODES_MAX_NUM_STEPS");
    if (max_num_steps_s != NULL)
    {
        long max_num_steps = atol(max_num_steps_s);
        retval = CVodeSetMaxNumSteps(cvode_mem, max_num_steps);
        if (check_retval(&retval, "CVodeSetMaxNumSteps", 1))
        {
            goto cleanup;
        }
    }

    retval = CVodeSetMaxNumSteps(cvode_mem, 1000000);
    if (check_retval(&retval, "CVodeSetMaxNumSteps", 1))
    {
        goto cleanup;
    }

    /* Time points */
    sunrealtype t;

    yout = New_Serial(NV_LENGTH_S(initial_values));
    const int result_rows = cuqdyn_conf->ode_expr.y_count;
    result = NewDenseMatrix(result_rows, NV_LENGTH_S(times));

    for (int i = 0; i < NV_LENGTH_S(times); ++i)
    {
        const sunrealtype actual_time = NV_Ith_S(times, i);

        if (actual_time == t0)
        {
            memcpy(SM_COLUMN_D(result, i), NV_DATA_S(initial_values),
                   NV_LENGTH_S(initial_values) * sizeof(sunrealtype));
            continue;
        }

        retval = CVode(cvode_mem, actual_time, yout, &t, CV_NORMAL);

        if (check_retval(&retval, "CVode", 1))
        {
            goto cleanup;
        }

        memcpy(SM_COLUMN_D(result, i), NV_DATA_S(yout), NV_LENGTH_S(yout) * sizeof(sunrealtype));
    }

    failed = 0;

cleanup:
    N_VDestroy(yout);

    if (cvode_mem != NULL)
    {
        // CVodeFree also releases the tolerance vector it was handed.
        CVodeFree(&cvode_mem);
    }
    else
    {
        N_VDestroy(cloned_abs_tol);
    }

    SUNLinSolFree(LS);
    SUNMatDestroy(A);

    if (failed && result != NULL)
    {
        SUNMatDestroy(result);
        result = NULL;
    }

    return result;
}

int check_retval(void *returnvalue, const char *funcname, int opt)
{
    /* Check if SUNDIALS function returned NULL pointer - no memory allocated */
    if (opt == 0 && returnvalue == NULL)
    {
        fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed - returned NULL pointer\n\n", funcname);
        return (1);
    }

    if (opt == 1)
    {
        int *retval = returnvalue;
        if (*retval < 0)
        {
            fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed with retval = %d\n\n", funcname, *retval);
            return (1);
        }
    }

    return (0);
}
