#include <../include/functions.h>
#include <config.h>
#include <cvodes_old/cvodes.h>
#include <ode_solver.h>
#include <string.h>
#include <sundials_old/sundials_nvector.h>

#include "cuqdyn.h"

ODEModel create_ode_model(N_Vector initial_values, realtype t0, N_Vector times)
{
    ODEModel ode_model;
    ode_model.initial_values = initial_values;
    ode_model.t0 = t0;
    ode_model.times = times;
    return ode_model;
}

void destroy_ode_model(ODEModel model)
{
    N_VDestroy(model.initial_values);
    N_VDestroy(model.times);
}

static int check_retval(void *, const char *, int);

DlsMat solve_ode(N_Vector parameters, ODEModel ode_model)
{
    CuqdynConf *cuqdyn_conf = get_cuqdyn_conf();
    Tolerances tolerances = cuqdyn_conf->tolerances;

    int retval;
    void *cvode_mem = CVodeCreate(CV_ADAMS, CV_FUNCTIONAL);
    if (check_retval((void*)cvode_mem, "CVodeCreate", 0)) { return NULL; }

    retval = CVodeInit(cvode_mem, ode_model_fun, ode_model.t0, ode_model.initial_values);
    if (check_retval(&retval, "CVodeInit", 1)) { return NULL; }

    N_Vector cloned_abs_tol = N_VNew_Serial(NV_LENGTH_S(tolerances.atol));
    memcpy(NV_DATA_S(cloned_abs_tol), NV_DATA_S(tolerances.atol), NV_LENGTH_S(tolerances.atol) * sizeof(realtype));

    // We clone the tolerances because the CVodeFree function frees the memory allocated for the abs_tol it receives
    retval = CVodeSVtolerances(cvode_mem, tolerances.rtol, cloned_abs_tol);
    if (check_retval(&retval, "CVodeSVtolerances", 1)) { return NULL; }

    retval = CVodeSetUserData(cvode_mem, parameters);
    if (check_retval(&retval, "CVodeSetUserData", 1)) { return NULL; }

    retval = CVodeSetMaxNumSteps(cvode_mem, 500000);
    if (check_retval(&retval, "CVodeSetMaxNumSteps", 1)) { return NULL; }

    /* Time points */
    realtype t;
    N_Vector times = ode_model.times;

    int retvalr;

    N_Vector yout = N_VNew_Serial(NV_LENGTH_S(ode_model.initial_values));
    int result_cols = cuqdyn_conf->ode_expr.y_count + 1; // We add the time col
    DlsMat result = SUNDenseMatrix(NV_LENGTH_S(times), result_cols);

    for (int i = 0; i < NV_LENGTH_S(times); ++i)
    {
        const realtype actual_time = NV_Ith_S(times, i);

        if (actual_time == ode_model.t0)
        {
            SM_ELEMENT_D(result, i, 0) = ode_model.t0;
            for (int j = 0; j < cuqdyn_conf->ode_expr.y_count; j++)
            {
                SM_ELEMENT_D(result, i, j + 1) = NV_Ith_S(ode_model.initial_values, j);
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