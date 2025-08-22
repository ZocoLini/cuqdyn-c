#include <functions.h>
#include <method_module/structure_paralleltestbed.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "cuqdyn.h"
#include "ode_solver.h"
#include "states_transformer.h"

extern void eval_f_exprs(sunrealtype t, sunrealtype *y, sunrealtype *ydot, sunrealtype *params, CuqDynContext context);

int ode_model_fun(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    N_Vector params_vec = user_data;
    sunrealtype *params = NV_DATA_S(params_vec);
    sunrealtype *ydot_pointer = NV_DATA_S(ydot);
    sunrealtype *y_pointer = NV_DATA_S(y);

#ifdef DEBUG
    fprintf(stdout, "[DEBUG] [ODE MODEL FUN] ");
    fprintf(stdout, "t: %f\n", t);
#endif

    eval_f_exprs(t, y_pointer, ydot_pointer, params, get_cuqdyn_context());

    return 0;
}

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
    fprintf(stdout, "[DEBUG] [OBJ FUNC] ");
    fprintf(stdout, "Params: ");
    for (int i = 0; i < NV_LENGTH_S(parameters); i++)
    {
        fprintf(stdout, "%f ", NV_Ith_S(parameters, i));
    }
    fprintf(stdout, "\n");
#endif

    const sunrealtype t0 = NV_Ith_S(texp, 0);

    TransposedStates ode_solution = solve_ode(parameters, exptotal->initial_values, t0, texp);
    ObservablesTransposedStates result = transform_states(ode_solution);

    const long rows = SM_ROWS_D(result);
    const long cols = SM_COLUMNS_D(result);
    sunrealtype J = 0.0;

    if (SM_ROWS_D(exptotal->yexp) != rows)
    {
        fprintf(stderr, "ERROR: The yexp rows don't match the ode result rows: %ld vs %ld\n", SM_ROWS_D(exptotal->yexp),
                rows);
        exit(-1);
    }

    if (SM_COLUMNS_D(exptotal->yexp) != cols)
    {
        fprintf(stderr, "ERROR: The yexp cols don't match the ode result cols: %ld vs %ld\n",
                SM_COLUMNS_D(exptotal->yexp), cols - 1);
        exit(-1);
    }

    for (long i = 0; i < rows; ++i)
    {
        for (long j = 0; j < cols; ++j)
        {
            const sunrealtype diff = SM_ELEMENT_D(result, i, j) - SM_ELEMENT_D(exptotal->yexp, i, j);
            J += diff * diff;
        }
    }

    res->value = J;

    N_VDestroy(parameters);
    SUNMatDestroy(result);

    return res;
}
