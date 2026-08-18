#include <functions.h>
#include <math.h>
#include <method_module/structure_paralleltestbed.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "cuqdyn.h"
#include "ode_solver.h"
#include "sundials/sundials_types.h"

extern void eval_f_exprs(sunrealtype t, sunrealtype *y, sunrealtype *ydot, sunrealtype *params, CuqDynContext context);

int ode_model_fun(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());

    N_Vector params_vec = user_data;
    sunrealtype *params = NV_DATA_S(params_vec);
    sunrealtype *ydot_pointer = NV_DATA_S(ydot);
    sunrealtype *y_pointer = NV_DATA_S(y);

    t /= conf->time_scaling;

#ifdef DEBUG
    fprintf(stdout, "[DEBUG] [ODE MODEL FUN] ");
    fprintf(stdout, "t: %f\n", t);
#endif

    eval_f_exprs(t, y_pointer, ydot_pointer, params, get_cuqdyn_context());

    return 0;
}

/*
 * Weight of observed state j, mirroring cuqdyn_weight_residuals.m.
 * 'none' leaves residuals untouched, 'known_sigma' divides by the measurement
 * standard deviation, and 'state_weights' multiplies by a user-supplied weight.
 */
sunrealtype cuqdyn_residual_weight(const CostOptions *cost, const int observed_state)
{
    switch (cost->residual_model)
    {
        case RESIDUAL_MODEL_KNOWN_SIGMA:
        {
            if (cost->sigma == NULL || cost->sigma_len == 0)
            {
                fprintf(stderr, "ERROR: residual_model=known_sigma needs <sigma> in the config\n");
                exit(-1);
            }
            // A single sigma applies to every observed state.
            const int index = cost->sigma_len == 1 ? 0 : observed_state;
            if (index >= cost->sigma_len)
            {
                fprintf(stderr, "ERROR: <sigma> has %d values but observed state %d was requested\n", cost->sigma_len,
                        observed_state);
                exit(-1);
            }
            const double sigma = fabs(cost->sigma[index]);
            return 1.0 / (sigma > cost->sigma_floor ? sigma : cost->sigma_floor);
        }

        case RESIDUAL_MODEL_STATE_WEIGHTS:
        {
            if (cost->weights == NULL || cost->weights_len == 0)
            {
                fprintf(stderr, "ERROR: residual_model=state_weights needs <observed_state_weights>\n");
                exit(-1);
            }
            const int index = cost->weights_len == 1 ? 0 : observed_state;
            return cost->weights[index];
        }

        default:
            return 1.0;
    }
}

/*
 * Weighted least-squares cost over the observed states only.
 *
 * Mirrors prob_mod_cost_Generic.m: solve the ODE for every state, keep the rows
 * the data actually measures, weight the residuals, and sum their squares.
 * When every state is observed this reduces to the plain sum of squared
 * residuals, which is the original CUQDyn1 objective.
 */
void *obj_func(double *x, void *data)
{
    CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());
    experiment_total *exptotal = data;
    output_function *res = calloc(1, sizeof(output_function));

    N_Vector parameters = New_Serial(conf->ode_expr.p_count);
    memcpy(NV_DATA_S(parameters), x, NV_LENGTH_S(parameters) * sizeof(sunrealtype));

    N_Vector texp = New_Serial(NV_LENGTH_S(exptotal->texp));
    memcpy(NV_DATA_S(texp), NV_DATA_S(exptotal->texp), NV_LENGTH_S(exptotal->texp) * sizeof(sunrealtype));

#ifdef DEBUG
    fprintf(stdout, "[DEBUG] [OBJ FUNC] Params: ");
    for (int i = 0; i < NV_LENGTH_S(parameters); i++)
    {
        fprintf(stdout, "%f ", NV_Ith_S(parameters, i));
    }
    fprintf(stdout, "\n");
#endif

    const sunrealtype t0 = NV_Ith_S(texp, 0);

    TransposedStates result = solve_ode(parameters, exptotal->initial_values, t0, texp);
    if (result == NULL)
    {
        fprintf(stderr, "ERROR: the ODE solver failed inside the objective function\n");
        exit(-1);
    }

    const long cols = SM_COLUMNS_D(result);
    const long available = SM_ROWS_D(result);

    // Rows of yexp are the measured states; observed_idx says where each one
    // sits in the ODE solution.
    const long n_obs = SM_ROWS_D(exptotal->yexp);

    if (SM_COLUMNS_D(exptotal->yexp) != cols)
    {
        fprintf(stderr, "ERROR: yexp has %ld time points but the ODE result has %ld\n", SM_COLUMNS_D(exptotal->yexp),
                cols);
        exit(-1);
    }

    double *J = malloc(sizeof(double));
    *J = 0.0;
    double *R = malloc(sizeof(double) * n_obs * cols);

    for (long j = 0; j < n_obs; ++j)
    {
        const long state = exptotal->observed_idx[j];

        if (state >= available)
        {
            fprintf(stderr, "ERROR: observed state %ld is outside the %ld available states\n", state, available);
            exit(-1);
        }

        const sunrealtype weight = cuqdyn_residual_weight(&conf->cost, (int) j);

        for (long i = 0; i < cols; ++i)
        {
            const sunrealtype difference = SM_ELEMENT_D(result, state, i) - SM_ELEMENT_D(exptotal->yexp, j, i);
            const sunrealtype weighted = difference * weight;

            R[j * cols + i] = weighted;
            *J += weighted * weighted;
        }
    }

    res->size_j = 1;
    res->J = J;
    res->value = *J;
    res->size_r = n_obs * cols;
    res->R = R;
    // No constraints are declared, and deallocateoutputfunction_ only frees g
    // when there are, so allocating it here would leak once per evaluation.
    res->g = NULL;

    N_VDestroy(parameters);
    N_VDestroy(texp);
    SUNMatDestroy(result);

    return res;
}
