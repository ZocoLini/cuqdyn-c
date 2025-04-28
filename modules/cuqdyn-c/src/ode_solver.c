#include <config.h>
#include <cvodes_old/cvodes.h>
#include <ode_solver.h>
#include <string.h>
#include <sundials_old/sundials_nvector.h>

#include "cuqdyn.h"

ODEModel create_ode_model(int number_eq, OdeModelFun f, N_Vector initial_values, realtype t0)
{
    ODEModel ode_model;
    ode_model.f = f;
    ode_model.number_eq = number_eq;
    ode_model.initial_values = initial_values;
    ode_model.t0 = t0;
    return ode_model;
}

void destroy_ode_model(ODEModel model)
{
    N_VDestroy(model.initial_values);
}

static int check_retval(void *, const char *, int);

/*
 * Solves the ODE system using the ode45 solver
 *
 * initial_values: data_matrix(1,2:end);
 * times: data_matrix(:,1);
 * parameters: constants to use in the ode
 *
 * Returns:
 *   DlsMat where:
 *   - Each row corresponds to a time point
 *   - Column 0: Time values (t)
 *   - Columns 1-n: Solution components (y1, y2, ..., yn)
 *
 */
DlsMat solve_ode(N_Vector parameters, ODEModel ode_model)
{
    CuqdynConf *cuqdyn_conf = get_cuqdyn_conf();
    Tolerances tolerances = cuqdyn_conf->tolerances;
    TimeConstraints time_constraints = cuqdyn_conf->time_constraints;

    int retval;
    void *cvode_mem = CVodeCreate(CV_BDF, CV_FUNCTIONAL);
    if (check_retval((void*)cvode_mem, "CVodeCreate", 0)) { return NULL; }

    retval = CVodeInit(cvode_mem, ode_model.f, ode_model.t0, ode_model.initial_values);
    if (check_retval(&retval, "CVodeInit", 1)) { return NULL; }

    N_Vector cloned_abs_tol = N_VNew_Serial(ode_model.number_eq, get_sun_context());
    memcpy(N_VGetArrayPointer(cloned_abs_tol), N_VGetArrayPointer(tolerances.abs_tol), ode_model.number_eq * sizeof(realtype));

    // We clone the tolerances because the CVodeFree function frees the memory allocated for the abs_tol it receives
    retval = CVodeSVtolerances(cvode_mem, tolerances.scalar_rtol, cloned_abs_tol);
    if (check_retval(&retval, "CVodeSVtolerances", 1)) { return NULL; }

    retval = CVodeSetUserData(cvode_mem, parameters);
    if (check_retval(&retval, "CVodeSetUserData", 1)) { return NULL; }

    retval = CVodeSetMaxNumSteps(cvode_mem, 500000);
    if (check_retval(&retval, "CVodeSetMaxNumSteps", 1)) { return NULL; }


    /* Time points */
    realtype t;
    realtype tinc = time_constraints.tinc;
    realtype tout = time_constraints.first_output_time;
    const realtype tf = time_constraints.tf + tinc;

    int retvalr;
    realtype *y_result = N_VGetArrayPointer(ode_model.initial_values);

    int result_rows = time_constraints_steps(time_constraints);
    int result_cols = ode_model.number_eq + 1; // We add the time col
    DlsMat result = SUNDenseMatrix(result_rows, result_cols, get_sun_context());

    int actual_result_matrix_row = 0;

    while (tout < tf)
    {
        retval = CVode(cvode_mem, tout, ode_model.initial_values, &t, CV_NORMAL);

        if (retval == CV_ROOT_RETURN)
        {
            int rootsfound[2];
            retvalr = CVodeGetRootInfo(cvode_mem, rootsfound);
            if (check_retval(&retvalr, "CVodeGetRootInfo", 1))
            {
                return NULL;
            }
        }

        if (check_retval(&retval, "CVode", 1))
        {
            return NULL;
        }
        if (retval == CV_SUCCESS)
        {
            tout += tinc;
        }

        // We are adding the time (t) as the first column but maybe we don't need it
        SM_ELEMENT_D(result, actual_result_matrix_row, 0) = t;

        for (int i = 0; i < ode_model.number_eq; i++)
        {
            SM_ELEMENT_D(result, actual_result_matrix_row, i + 1) = y_result[i];
        }

        actual_result_matrix_row++;
    }

    CVodeFree(&cvode_mem);

    return result;
}

int check_retval(void *returnvalue, const char *funcname, int opt)
{
    int *retval;

    /* Check if SUNDIALS function returned NULL pointer - no memory allocated */
    if (opt == 0 && returnvalue == NULL)
    {
        fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed - returned NULL pointer\n\n", funcname);
        return (1);
    }

    /* Check if retval < 0 */
    else if (opt == 1)
    {
        retval = (int *) returnvalue;
        if (*retval < 0)
        {
            fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed with retval = %d\n\n", funcname, *retval);
            return (1);
        }
    }

    /* Check if function returned NULL pointer - no memory allocated */
    else if (opt == 2 && returnvalue == NULL)
    {
        fprintf(stderr, "\nMEMORY_ERROR: %s() failed - returned NULL pointer\n\n", funcname);
        return (1);
    }

    return (0);
}