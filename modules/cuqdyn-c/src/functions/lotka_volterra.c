#include <functions/lotka_volterra.h>
#include <method_module/structure_paralleltestbed.h>
#include <nvector_old/nvector_serial.h>
#include <string.h>
#include <sundials_old/sundials_direct.h>
#include <sundials_old/sundials_nvector.h>

#include "config.h"
#include "cuqdyn.h"
#include "sundials_old/sundials_types.h"

extern void lotka_volterra_f_rs(realtype t, realtype *y, realtype *ydot,
                                realtype *params, int n);

int ode_model_fun(realtype t, N_Vector y, N_Vector ydot, void *user_data) {
  realtype *params = N_VGetArrayPointer(user_data);
  realtype *ydot_pointer = N_VGetArrayPointer(ydot);
  realtype *y_pointer = N_VGetArrayPointer(y);

  CuqdynConf *conf = get_cuqdyn_conf();

  lotka_volterra_f_rs(t, y_pointer, ydot_pointer, params, conf->tolerances.odes_count);

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
void *ode_model_obj_func(double *x, void *data) {
  experiment_total *exptotal = data;
  output_function *res = calloc(1, sizeof(output_function));

  N_Vector parameters = N_VNew_Serial(4, get_sun_context());
  NV_Ith_S(parameters, 0) = x[0];
  NV_Ith_S(parameters, 1) = x[1];
  NV_Ith_S(parameters, 2) = x[2];
  NV_Ith_S(parameters, 3) = x[3];

  N_Vector initial_values =
      N_VNew_Serial(NV_LENGTH_S(exptotal->initial_values), get_sun_context());
  memcpy(N_VGetArrayPointer(initial_values),
         N_VGetArrayPointer(exptotal->initial_values),
         NV_LENGTH_S(exptotal->initial_values) * sizeof(realtype));

  N_Vector times =
      N_VNew_Serial(NV_LENGTH_S(exptotal->texp), get_sun_context());
  memcpy(N_VGetArrayPointer(times), N_VGetArrayPointer(exptotal->texp),
         NV_LENGTH_S(exptotal->texp) * sizeof(realtype));

  const realtype t0 = NV_Ith_S(times, 0);

  const ODEModel ode_model =
      create_ode_model(2, initial_values, t0, times);

  DlsMat result = solve_ode(parameters, ode_model);

  // Objective function code:
  realtype J = 0.0;
  long int rows = SM_ROWS_D(result);
  long int cols = SM_COLUMNS_D(result);

  for (long int i = 0; i < rows; ++i) {
    for (long int j = 1; j < cols; ++j) {
      realtype diff =
          SM_ELEMENT_D(result, i, j) - SM_ELEMENT_D(exptotal->yexp, i, j - 1);
      J += diff * diff;
    }
  }

  // Free resources
  N_VDestroy(parameters);
  destroy_ode_model(ode_model);
  SUNMatDestroy(result);

  res->value = J;

  return res;
}
