#ifndef EDO_SOLVER_H
#define EDO_SOLVER_H

#include <nvector/nvector_serial.h>
#include <sundials/sundials_matrix.h>
#include <sundials/sundials_types.h>

#include "cuqdyn.h"

/*
 * Trajectory sensitivities dy_k(t_i)/dtheta_j.
 *
 * The Matlab toolbox obtains these with complex-step differentiation, which
 * needs the ODE to be integrated in complex arithmetic. CVODES cannot do that,
 * but it computes forward sensitivities natively: one augmented integration
 * yields every dy/dtheta instead of n_params separate perturbed solves.
 */
typedef struct
{
    TransposedStates *data;
    int n_params;
    long n_states;
    long n_times;
} Sensitivities;

void destroy_sensitivities(Sensitivities sensitivities);
/// dy_state(t_time) / dtheta_param
sunrealtype sensitivity_at(Sensitivities sensitivities, long state, long time, int param);

/*
 * Solves the ODE at the given parameters, returning the trajectory as an
 * n_states x n_times matrix owned by the caller, or NULL on failure.
 *
 * Pass a non-NULL sensitivities_out to also get the forward sensitivities, in
 * which case CVODES integrates the augmented system in the same pass and
 * *sensitivities_out is filled on success (the caller then owns it and must
 * release it with destroy_sensitivities). Pass NULL to integrate the states
 * alone.
 *
 * This mirrors the reference toolbox, where a single ODE_solve serves both the
 * cost function and the UQ stage: sensitivities are not a property of the
 * solver but something only the delta-method bands ask for, once per run. The
 * cost function is evaluated millions of times and never needs them, so the
 * augmented system stays off its path.
 */
TransposedStates solve_ode(N_Vector parameters, N_Vector initial_values, sunrealtype t0, N_Vector times,
                           Sensitivities *sensitivities_out);

#endif // EDO_SOLVER_H
