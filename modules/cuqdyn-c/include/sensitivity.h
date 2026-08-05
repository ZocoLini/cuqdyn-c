#ifndef SENSITIVITY_H
#define SENSITIVITY_H

#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

#include "cuqdyn.h"

/*
 * Trajectory sensitivities dy_k(t_i)/dtheta_j.
 *
 * The Matlab toolbox obtains these with complex-step differentiation, which
 * needs the ODE to be integrated in complex arithmetic. CVODES cannot do that,
 * but it computes forward sensitivities natively: one augmented integration
 * yields every dy/dtheta instead of n_params separate perturbed solves.
 *
 * Layout mirrors the transposed convention used across the library: `data`
 * holds one n_states x n_times matrix per parameter.
 */
typedef struct
{
    SUNMatrix *data;
    int n_params;
    long n_states;
    long n_times;
} Sensitivities;

Sensitivities create_sensitivities(int n_params, long n_states, long n_times);
void destroy_sensitivities(Sensitivities sensitivities);
/// dy_state(t_time) / dtheta_param
sunrealtype sensitivity_at(Sensitivities sensitivities, long state, long time, int param);

/*
 * Integrates the ODE and its forward sensitivities in a single pass.
 *
 * On success *states_out receives the trajectory (n_states x n_times, owned by
 * the caller) and *sensitivities_out the sensitivities. Returns 0 on success.
 */
int solve_ode_with_sensitivities(N_Vector parameters, N_Vector initial_values, sunrealtype t0, N_Vector times,
                                 TransposedStates *states_out, Sensitivities *sensitivities_out);

#endif // SENSITIVITY_H
