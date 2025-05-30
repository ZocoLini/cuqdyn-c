#include <../include/functions.h>
#include <method_module/structure_paralleltestbed.h>
#include <nvector_old/nvector_serial.h>
#include <string.h>
#include <sundials_old/sundials_direct.h>
#include <sundials_old/sundials_nvector.h>

#include "config.h"
#include "cuqdyn.h"
#include "sundials_old/sundials_types.h"

extern void mexpreval_init(OdeExpr ode_expr);

void mexpreval_init_wrapper(OdeExpr ode_expr)
{
    mexpreval_init(ode_expr);
}

extern void eval_f_exprs(realtype t, realtype *y, realtype *ydot, realtype *params);

int ode_model_fun(realtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    N_Vector params_vec = user_data;
    realtype *params = NV_DATA_S(params_vec);
    realtype *ydot_pointer = NV_DATA_S(ydot);
    realtype *y_pointer = NV_DATA_S(y);

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
void *ode_model_obj_func(double *x, void *data)
{
    CuqdynConf *conf = get_cuqdyn_conf();
    experiment_total *exptotal = data;
    output_function *res = calloc(1, sizeof(output_function));

    N_Vector parameters = N_VNew_Serial(conf->ode_expr.p_count);
    memcpy(NV_DATA_S(parameters), x, NV_LENGTH_S(parameters) * sizeof(realtype));

    N_Vector texp = N_VNew_Serial(NV_LENGTH_S(exptotal->texp));
    memcpy(NV_DATA_S(texp), NV_DATA_S(exptotal->texp), NV_LENGTH_S(exptotal->texp) * sizeof(realtype));

    const realtype t0 = NV_Ith_S(texp, 0);

    DlsMat result = solve_ode(parameters, exptotal->initial_values, t0, texp);

    // Objective function code:
    const int rows = SM_ROWS_D(result);
    const int cols = SM_COLUMNS_D(result);

    // realtype R[(cols - 1) * rows];
    realtype J = 0.0;

    long index = 0;

    for (long i = 0; i < rows; ++i)
    {
        // Note that the first col of the result matrix is t
        for (long j = 1; j < cols; ++j)
        {
            const realtype diff = SM_ELEMENT_D(result, i, j) - SM_ELEMENT_D(exptotal->yexp, i, j - 1);
            J += diff * diff;
            // R[index++] = SM_ELEMENT_D(result, i, j) - SM_ELEMENT_D(exptotal->yexp, i, j - 1);
        }
    }

    // TODO: I'm not sure about this. res->J is a pointer what makes no sense
    res->value = J;
    // res->g = 0;
    // res->R = R;
    // res->size_r = (cols - 1) * rows;

    N_VDestroy(parameters);
    SUNMatDestroy(result);

    return res;
}
