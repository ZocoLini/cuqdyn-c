#include <config.h>
#include <cvodes/cvodes.h>
#include <functions.h>
#include <math.h>
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

static Sensitivities create_sensitivities(const int n_params, const long n_states, const long n_times)
{
    Sensitivities sensitivities;
    sensitivities.n_params = n_params;
    sensitivities.n_states = n_states;
    sensitivities.n_times = n_times;
    sensitivities.data = (TransposedStates *) calloc(n_params, sizeof(TransposedStates));

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

    free((void *) sensitivities.data);
}

sunrealtype sensitivity_at(const Sensitivities sensitivities, const long state, const long time, const int param)
{
    return SM_ELEMENT_D(sensitivities.data[param], state, time);
}


/*
 * The cost function calls solve_ode once per evaluation, which is millions of
 * times a run. Building CVODES from scratch each time (CVodeCreate, CVodeInit,
 * the dense matrix and linear solver) made it the source of nearly every malloc
 * in the program, so the plain path keeps one integrator alive and only
 * CVodeReInit's it. CVodeReInit resets the whole integration state, so the
 * trajectory is the same as from a fresh one.
 *
 * One per thread, since saCeSS can evaluate the cost from OpenMP threads. The
 * sensitivity path runs once per run and still builds its own, which keeps
 * CVodeSensInit off the shared integrator.
 */
typedef struct
{
    void *cvode_mem;
    SUNMatrix A;
    SUNLinearSolver LS;
    N_Vector abs_tol;
    N_Vector yout;
    long n_states;
    long atol_len;
} OdeWorkspace;

static _Thread_local OdeWorkspace workspace;

static void free_integrator(void **cvode_mem, SUNLinearSolver *LS, SUNMatrix *A)
{
    if (*cvode_mem != NULL)
    {
        CVodeFree(cvode_mem);
    }
    SUNLinSolFree(*LS);
    SUNMatDestroy(*A);
    *LS = NULL;
    *A = NULL;
}

/*
 * Creates a CVODES integrator for y' = ode_model_fun, with its dense linear
 * solver and the step limits from the environment. Tolerances and user data
 * are left to the caller, since they change between calls. Returns NULL on
 * failure, with nothing left allocated.
 */
static void *create_integrator(N_Vector initial_values, sunrealtype t0, long n_states, SUNMatrix *A_out,
                               SUNLinearSolver *LS_out)
{
    int retval;
    SUNMatrix A = NULL;
    SUNLinearSolver LS = NULL;

    void *cvode_mem = CVodeCreate(CV_BDF, get_sundials_ctx());
    if (check_retval((void *) cvode_mem, "CVodeCreate", 0))
    {
        return NULL;
    }

    retval = CVodeInit(cvode_mem, ode_model_fun, t0, initial_values);
    if (check_retval(&retval, "CVodeInit", 1))
    {
        goto fail;
    }

    A = NewDenseMatrix(n_states, n_states);
    LS = SUNLinSol_Dense(initial_values, A, get_sundials_ctx());
    retval = CVodeSetLinearSolver(cvode_mem, LS, A);
    if (check_retval(&retval, "CVodeSetLinearSolver", 1))
    {
        goto fail;
    }

    // Without a Jacobian function CVODES builds it by finite differences, one
    // extra RHS evaluation per state on every Newton matrix refresh.
    // CUQDYN_DQ_JACOBIAN keeps that path available for comparison.
    if (has_jacobian(get_cuqdyn_context()) && getenv("CUQDYN_DQ_JACOBIAN") == NULL)
    {
        retval = CVodeSetJacFn(cvode_mem, ode_model_jac);
        if (check_retval(&retval, "CVodeSetJacFn", 1))
        {
            goto fail;
        }
    }

    char *min_step_s = getenv("CUQDYN_CVODES_MIN_STEP");
    if (min_step_s != NULL)
    {
        sunrealtype min_step = atof(min_step_s);
        retval = CVodeSetMinStep(cvode_mem, min_step);
        if (check_retval(&retval, "CVodeSetMinStep", 1))
        {
            goto fail;
        }
    }

    long max_num_steps = 1000000;
    char *max_num_steps_s = getenv("CUQDYN_CVODES_MAX_NUM_STEPS");
    if (max_num_steps_s != NULL)
    {
        max_num_steps = atol(max_num_steps_s);
    }

    retval = CVodeSetMaxNumSteps(cvode_mem, max_num_steps);
    if (check_retval(&retval, "CVodeSetMaxNumSteps", 1))
    {
        goto fail;
    }

    *A_out = A;
    *LS_out = LS;
    return cvode_mem;

fail:
    free_integrator(&cvode_mem, &LS, &A);
    return NULL;
}

void release_ode_workspace(void)
{
    free_integrator(&workspace.cvode_mem, &workspace.LS, &workspace.A);
    N_VDestroy(workspace.abs_tol);
    N_VDestroy(workspace.yout);
    workspace = (OdeWorkspace) {0};
}

/*
 * The integrator of the plain path, rewound to (t0, initial_values). It is
 * rebuilt only when the model it was sized for changes.
 */
static void *reuse_integrator(N_Vector initial_values, sunrealtype t0, long n_states, long atol_len)
{
    if (workspace.cvode_mem != NULL && workspace.n_states == n_states && workspace.atol_len == atol_len)
    {
        int retval = CVodeReInit(workspace.cvode_mem, t0, initial_values);
        if (!check_retval(&retval, "CVodeReInit", 1))
        {
            return workspace.cvode_mem;
        }
    }

    release_ode_workspace();

    workspace.cvode_mem = create_integrator(initial_values, t0, n_states, &workspace.A, &workspace.LS);
    if (workspace.cvode_mem == NULL)
    {
        return NULL;
    }

    workspace.abs_tol = New_Serial(atol_len);
    workspace.yout = New_Serial(n_states);
    workspace.n_states = n_states;
    workspace.atol_len = atol_len;

    return workspace.cvode_mem;
}

TransposedStates solve_ode(N_Vector parameters, N_Vector initial_values, sunrealtype t0, N_Vector times,
                           Sensitivities *sensitivities_out)
{
    CuqdynConf *cuqdyn_conf = get_cuqdyn_conf(get_cuqdyn_context());
    Tolerances tolerances = cuqdyn_conf->tolerances;

    const int n_params = cuqdyn_conf->ode_expr.p_count;
    const long n_states = cuqdyn_conf->ode_expr.y_count;
    const long n_times = NV_LENGTH_S(times);
    const int with_sensitivities = sensitivities_out != NULL;

    if (NV_LENGTH_S(initial_values) != n_states)
    {
        // The trajectory columns and the dense Jacobian are both sized from
        // y_count, so a mismatched y0 would be read past its end.
        fprintf(stderr, "ERROR: initial condition has %ld entries, expected %ld\n", NV_LENGTH_S(initial_values),
                n_states);
        return NULL;
    }

    if (with_sensitivities && NV_LENGTH_S(parameters) != n_params)
    {
        // CVodeSetSensParams reads n_params entries out of this vector.
        fprintf(stderr, "ERROR: parameter vector has %ld entries, expected %d\n", NV_LENGTH_S(parameters), n_params);
        return NULL;
    }

    int retval;
    void *cvode_mem = NULL;
    // Only set on the sensitivity path; the plain one borrows the workspace's.
    SUNMatrix A = NULL;
    SUNLinearSolver LS = NULL;
    N_Vector own_abs_tol = NULL;
    N_Vector own_yout = NULL;
    N_Vector abs_tol;
    N_Vector yout;
    N_Vector *sensitivity_vectors = NULL;
    sunrealtype *pbar = NULL;
    Sensitivities sensitivities = {0};
    TransposedStates result = NULL;
    int failed = 1;

    if (with_sensitivities)
    {
        cvode_mem = create_integrator(initial_values, t0, n_states, &A, &LS);
        own_abs_tol = New_Serial(tolerances.atol_len);
        own_yout = New_Serial(n_states);
        abs_tol = own_abs_tol;
        yout = own_yout;
    }
    else
    {
        cvode_mem = reuse_integrator(initial_values, t0, n_states, tolerances.atol_len);
        abs_tol = workspace.abs_tol;
        yout = workspace.yout;
    }

    if (cvode_mem == NULL)
    {
        goto cleanup;
    }

    // CVodeSVtolerances copies the vector, and only allocates on its first call
    // for a given integrator.
    memcpy(NV_DATA_S(abs_tol), tolerances.atol, tolerances.atol_len * sizeof(sunrealtype));

    retval = CVodeSVtolerances(cvode_mem, tolerances.rtol, abs_tol);
    if (check_retval(&retval, "CVodeSVtolerances", 1))
    {
        goto cleanup;
    }

    retval = CVodeSetUserData(cvode_mem, parameters);
    if (check_retval(&retval, "CVodeSetUserData", 1))
    {
        goto cleanup;
    }

    if (with_sensitivities)
    {
        // The initial condition does not depend on the parameters, so every
        // sensitivity starts at zero.
        sensitivity_vectors = N_VCloneVectorArray(n_params, initial_values);
        for (int i = 0; i < n_params; ++i)
        {
            N_VConst(0.0, sensitivity_vectors[i]);
        }

        retval = CVodeSensInit(cvode_mem, n_params, CV_SIMULTANEOUS, NULL, sensitivity_vectors);
        if (check_retval(&retval, "CVodeSensInit", 1))
        {
            goto cleanup;
        }

        retval = CVodeSensEEtolerances(cvode_mem);
        if (check_retval(&retval, "CVodeSensEEtolerances", 1))
        {
            goto cleanup;
        }

        retval = CVodeSetSensErrCon(cvode_mem, SUNTRUE);
        if (check_retval(&retval, "CVodeSetSensErrCon", 1))
        {
            goto cleanup;
        }

        // Without an analytic sensitivity RHS, CVODES perturbs the parameter
        // array in place and re-evaluates the model. That array must be the very
        // one the RHS reads, which is the user data set above. pbar carries the
        // magnitudes so the difference quotients stay well scaled across
        // parameters.
        pbar = malloc(n_params * sizeof(sunrealtype));
        for (int i = 0; i < n_params; ++i)
        {
            const sunrealtype value = fabs(NV_Ith_S(parameters, i));
            pbar[i] = value > 0.0 ? value : 1.0;
        }

        retval = CVodeSetSensParams(cvode_mem, NV_DATA_S(parameters), pbar, NULL);
        if (check_retval(&retval, "CVodeSetSensParams", 1))
        {
            goto cleanup;
        }

        sensitivities = create_sensitivities(n_params, n_states, n_times);
    }

    /* Time points */
    sunrealtype t;

    result = NewDenseMatrix(n_states, n_times);

    for (long i = 0; i < n_times; ++i)
    {
        const sunrealtype actual_time = NV_Ith_S(times, i);

        if (actual_time == t0)
        {
            memcpy(SM_COLUMN_D(result, i), NV_DATA_S(initial_values), n_states * sizeof(sunrealtype));
            // Sensitivities are already zero at t0.
            continue;
        }

        retval = CVode(cvode_mem, actual_time, yout, &t, CV_NORMAL);

        if (check_retval(&retval, "CVode", 1))
        {
            goto cleanup;
        }

        memcpy(SM_COLUMN_D(result, i), NV_DATA_S(yout), n_states * sizeof(sunrealtype));

        if (!with_sensitivities)
        {
            continue;
        }

        retval = CVodeGetSens(cvode_mem, &t, sensitivity_vectors);
        if (check_retval(&retval, "CVodeGetSens", 1))
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

    if (with_sensitivities)
    {
        *sensitivities_out = sensitivities;
        sensitivities.data = NULL; // ownership handed to the caller
    }

    failed = 0;

cleanup:
    destroy_sensitivities(sensitivities);
    free(pbar);

    if (with_sensitivities)
    {
        if (cvode_mem != NULL)
        {
            CVodeSensFree(cvode_mem);
        }
        free_integrator(&cvode_mem, &LS, &A);
        N_VDestroy(own_abs_tol);
        N_VDestroy(own_yout);
    }

    // CVodeSensInit copies the vectors it is handed, so these stay ours to free.
    if (sensitivity_vectors != NULL)
    {
        N_VDestroyVectorArray(sensitivity_vectors, n_params);
    }

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
