#include <../include/functions.h>
#include <config.h>
#include <cvodes/cvodes.h>
#include <ode_solver.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "cuqdyn.h"

static int check_retval(void *, const char *, int);

SUNMatrix solve_ode(N_Vector parameters, N_Vector initial_values, sunrealtype t0, N_Vector times)
{
    CuqdynConf *cuqdyn_conf = get_cuqdyn_conf();
    Tolerances tolerances = cuqdyn_conf->tolerances;

    int retval;
    void *cvode_mem = CVodeCreate(CV_ADAMS, get_sundials_ctx());
    if (check_retval((void*)cvode_mem, "CVodeCreate", 0)) { return NULL; }

    retval = CVodeInit(cvode_mem, ode_model_fun, t0, initial_values);
    if (check_retval(&retval, "CVodeInit", 1)) { return NULL; }

    N_Vector cloned_abs_tol = New_Serial(NV_LENGTH_S(tolerances.atol));
    memcpy(NV_DATA_S(cloned_abs_tol), NV_DATA_S(tolerances.atol), NV_LENGTH_S(tolerances.atol) * sizeof(sunrealtype));

    // We clone the tolerances because the CVodeFree function frees the memory allocated for the abs_tol it receives
    retval = CVodeSVtolerances(cvode_mem, tolerances.rtol, cloned_abs_tol);
    if (check_retval(&retval, "CVodeSVtolerances", 1)) { return NULL; }

    retval = CVodeSetUserData(cvode_mem, parameters);
    if (check_retval(&retval, "CVodeSetUserData", 1)) { return NULL; }

    retval = CVodeSetMaxNumSteps(cvode_mem, 10000000);
    if (check_retval(&retval, "CVodeSetMaxNumSteps", 1)) { return NULL; }

    /* Time points */
    sunrealtype t;

    N_Vector yout = New_Serial(NV_LENGTH_S(initial_values));
    int result_cols = cuqdyn_conf->ode_expr.y_count + 1; // We add the time col
    SUNMatrix result = NewDenseMatrix(NV_LENGTH_S(times), result_cols);

    for (int i = 0; i < NV_LENGTH_S(times); ++i)
    {
        const sunrealtype actual_time = NV_Ith_S(times, i);

        if (actual_time == t0)
        {
            SM_ELEMENT_D(result, i, 0) = t0;
            for (int j = 0; j < cuqdyn_conf->ode_expr.y_count; j++)
            {
                SM_ELEMENT_D(result, i, j + 1) = NV_Ith_S(initial_values, j);
            }
            continue;
        }

        retval = CVode(cvode_mem, actual_time, yout, &t, CV_NORMAL);

        if (check_retval(&retval, "CVode", 1))
        {
            return NULL;
        }

        SM_ELEMENT_D(result, i, 0) = t;

        for (int j = 0; j < cuqdyn_conf->ode_expr.y_count; j++)
        {
            SM_ELEMENT_D(result, i, j + 1) = NV_Ith_S(yout, j);
        }
    }

    N_VDestroy(yout);
    CVodeFree(&cvode_mem);

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