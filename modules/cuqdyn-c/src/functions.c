#include <../include/functions.h>
#include <method_module/structure_paralleltestbed.h>
#include <nvector/nvector_serial.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "cuqdyn.h"
#include "states_transformer.h"

extern void mexpreval_init(CuqdynConf cuqdyn_conf);

void mexpreval_init_wrapper(CuqdynConf cuqdyn_conf)
{
    mexpreval_init(cuqdyn_conf);
}

extern void eval_f_exprs(sunrealtype t, sunrealtype *y, sunrealtype *ydot, sunrealtype *params);

int ode_model_fun(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    N_Vector params_vec = user_data;
    sunrealtype *params = NV_DATA_S(params_vec);
    sunrealtype *ydot_pointer = NV_DATA_S(ydot);
    sunrealtype *y_pointer = NV_DATA_S(y);

    eval_f_exprs(t, y_pointer, ydot_pointer, params);

    return 0;
}

/*
 * function [J,g,R]=prob_mod_lv(x,texp,yexp)
 * [tout,yout] =
 * ode15s(@prob_mod_dynamics_lv,texp,[10,5],odeset('RelTol',1e-6,'AbsTol',1e-6*ones(1,2)),x);
 * R=(yout-yexp);
 * R=reshape(R,numel(R),1);
 * J = sum(sum((yout-yexp).^2));
 * g=0;
 * return
 */
void *obj_func(double *x, void *data)
{
    CuqdynConf *conf = get_cuqdyn_conf();
    experiment_total *exptotal = data;
    output_function *res = calloc(1, sizeof(output_function));

    N_Vector parameters = New_Serial(conf->ode_expr.p_count);
    memcpy(NV_DATA_S(parameters), x, NV_LENGTH_S(parameters) * sizeof(sunrealtype));

    N_Vector texp = New_Serial(NV_LENGTH_S(exptotal->texp));
    memcpy(NV_DATA_S(texp), NV_DATA_S(exptotal->texp), NV_LENGTH_S(exptotal->texp) * sizeof(sunrealtype));

    const sunrealtype t0 = NV_Ith_S(texp, 0);

    SUNMatrix result = solve_ode(parameters, exptotal->initial_values, t0, texp);
    result = transform_states(result);

    const long rows = SM_ROWS_D(result);
    const long cols = SM_COLUMNS_D(result);
    sunrealtype J = 0.0;

    if (SM_ROWS_D(exptotal->yexp) != rows)
    {
        fprintf(stderr, "ERROR: The yexp rows don't match the ode result rows: %ld vs %ld\n", SM_ROWS_D(exptotal->yexp), rows);
        exit(-1);
    }

    if (SM_COLUMNS_D(exptotal->yexp) != cols - 1)
    {
        fprintf(stderr, "ERROR: The yexp cols don't match the ode result cols: %ld vs %ld\n", SM_COLUMNS_D(exptotal->yexp), cols - 1);
        exit(-1);
    }

    for (long i = 0; i < rows; ++i)
    {
        // Note that the first col of the result matrix is t
        for (long j = 1; j < cols; ++j)
        {
            const sunrealtype diff = SM_ELEMENT_D(result, i, j) - SM_ELEMENT_D(exptotal->yexp, i, j - 1);
            J += diff * diff;
        }
    }

    res->value = J;

    N_VDestroy(parameters);
    SUNMatDestroy(result);

    return res;
}
