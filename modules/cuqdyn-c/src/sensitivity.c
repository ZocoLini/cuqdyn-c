#include "sensitivity.h"

#include <config.h>
#include <cvodes/cvodes.h>
#include <functions.h>
#include <math.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sunlinsol/sunlinsol_dense.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "cuqdyn.h"

Sensitivities create_sensitivities(const int n_params, const long n_states, const long n_times)
{
    Sensitivities sensitivities;
    sensitivities.n_params = n_params;
    sensitivities.n_states = n_states;
    sensitivities.n_times = n_times;
    sensitivities.data = calloc(n_params, sizeof(SUNMatrix));

    for (int i = 0; i < n_params; ++i)
    {
        sensitivities.data[i] = NewDenseMatrix(n_states, n_times);
    }

    return sensitivities;
}

void destroy_sensitivities(const Sensitivities sensitivities)
{
    if (sensitivities.data == NULL)
    {
        return;
    }

    for (int i = 0; i < sensitivities.n_params; ++i)
    {
        SUNMatDestroy(sensitivities.data[i]);
    }

    free(sensitivities.data);
}

sunrealtype sensitivity_at(const Sensitivities sensitivities, const long state, const long time, const int param)
{
    return SM_ELEMENT_D(sensitivities.data[param], state, time);
}

static int check(const int retval, const char *name)
{
    if (retval < 0)
    {
        fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed with retval = %d\n\n", name, retval);
        return 1;
    }
    return 0;
}

int solve_ode_with_sensitivities(N_Vector parameters, N_Vector initial_values, const sunrealtype t0, N_Vector times,
                                 TransposedStates *states_out, Sensitivities *sensitivities_out)
{
    const CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());
    const Tolerances tolerances = conf->tolerances;

    const int n_params = conf->ode_expr.p_count;
    const long n_states = conf->ode_expr.y_count;
    const long n_times = NV_LENGTH_S(times);

    if (NV_LENGTH_S(parameters) != n_params)
    {
        fprintf(stderr, "ERROR: parameter vector has %ld entries, expected %d\n", NV_LENGTH_S(parameters), n_params);
        return 1;
    }

    void *cvode_mem = NULL;
    SUNMatrix a = NULL;
    SUNLinearSolver linear_solver = NULL;
    N_Vector yout = NULL;
    N_Vector *sensitivity_vectors = NULL;
    N_Vector abs_tol = NULL;
    TransposedStates states = NULL;
    Sensitivities sensitivities = {0};
    sunrealtype *pbar = NULL;
    int failed = 1;

    cvode_mem = CVodeCreate(CV_BDF, get_sundials_ctx());
    if (cvode_mem == NULL)
    {
        fprintf(stderr, "\nSUNDIALS_ERROR: CVodeCreate() returned NULL\n\n");
        goto cleanup;
    }

    if (check(CVodeInit(cvode_mem, ode_model_fun, t0, initial_values), "CVodeInit"))
    {
        goto cleanup;
    }

    // CVodeFree releases the tolerance vector it is handed, so pass a clone.
    abs_tol = New_Serial(tolerances.atol_len);
    memcpy(NV_DATA_S(abs_tol), tolerances.atol, tolerances.atol_len * sizeof(sunrealtype));
    if (check(CVodeSVtolerances(cvode_mem, tolerances.rtol, abs_tol), "CVodeSVtolerances"))
    {
        goto cleanup;
    }

    if (check(CVodeSetUserData(cvode_mem, parameters), "CVodeSetUserData"))
    {
        goto cleanup;
    }

    a = NewDenseMatrix(n_states, n_states);
    linear_solver = SUNLinSol_Dense(initial_values, a, get_sundials_ctx());
    if (check(CVodeSetLinearSolver(cvode_mem, linear_solver, a), "CVodeSetLinearSolver"))
    {
        goto cleanup;
    }

    if (check(CVodeSetMaxNumSteps(cvode_mem, 1000000), "CVodeSetMaxNumSteps"))
    {
        goto cleanup;
    }

    // Forward sensitivity setup. The initial condition does not depend on the
    // parameters, so every sensitivity starts at zero.
    sensitivity_vectors = N_VCloneVectorArray(n_params, initial_values);
    for (int i = 0; i < n_params; ++i)
    {
        N_VConst(0.0, sensitivity_vectors[i]);
    }

    if (check(CVodeSensInit(cvode_mem, n_params, CV_SIMULTANEOUS, NULL, sensitivity_vectors), "CVodeSensInit"))
    {
        goto cleanup;
    }

    if (check(CVodeSensEEtolerances(cvode_mem), "CVodeSensEEtolerances"))
    {
        goto cleanup;
    }

    if (check(CVodeSetSensErrCon(cvode_mem, SUNTRUE), "CVodeSetSensErrCon"))
    {
        goto cleanup;
    }

    // Without an analytic sensitivity RHS, CVODES perturbs the parameter array
    // in place and re-evaluates the model. That array must be the very one the
    // RHS reads, which is the user data set above. pbar carries the magnitudes
    // so the difference quotients stay well scaled across parameters.
    pbar = malloc(n_params * sizeof(sunrealtype));
    for (int i = 0; i < n_params; ++i)
    {
        const sunrealtype value = fabs(NV_Ith_S(parameters, i));
        pbar[i] = value > 0.0 ? value : 1.0;
    }

    if (check(CVodeSetSensParams(cvode_mem, NV_DATA_S(parameters), pbar, NULL), "CVodeSetSensParams"))
    {
        goto cleanup;
    }

    states = NewDenseMatrix(n_states, n_times);
    sensitivities = create_sensitivities(n_params, n_states, n_times);
    yout = New_Serial(n_states);

    for (long i = 0; i < n_times; ++i)
    {
        const sunrealtype target = NV_Ith_S(times, i);

        if (target == t0)
        {
            memcpy(SM_COLUMN_D(states, i), NV_DATA_S(initial_values), n_states * sizeof(sunrealtype));
            // Sensitivities are already zero at t0.
            continue;
        }

        sunrealtype reached;
        if (check(CVode(cvode_mem, target, yout, &reached, CV_NORMAL), "CVode"))
        {
            goto cleanup;
        }

        memcpy(SM_COLUMN_D(states, i), NV_DATA_S(yout), n_states * sizeof(sunrealtype));

        if (check(CVodeGetSens(cvode_mem, &reached, sensitivity_vectors), "CVodeGetSens"))
        {
            goto cleanup;
        }

        for (int p = 0; p < n_params; ++p)
        {
            const sunrealtype *column = NV_DATA_S(sensitivity_vectors[p]);
            for (long k = 0; k < n_states; ++k)
            {
                SM_ELEMENT_D(sensitivities.data[p], k, i) = column[k];
            }
        }
    }

    *states_out = states;
    *sensitivities_out = sensitivities;
    states = NULL;
    sensitivities.data = NULL;
    failed = 0;

cleanup:
    SUNMatDestroy(states);
    destroy_sensitivities(sensitivities);
    N_VDestroy(yout);
    N_VDestroyVectorArray(sensitivity_vectors, n_params);
    free(pbar);

    if (cvode_mem != NULL)
    {
        CVodeSensFree(cvode_mem);
    }
    CVodeFree(&cvode_mem);

    SUNLinSolFree(linear_solver);
    SUNMatDestroy(a);

    return failed;
}
