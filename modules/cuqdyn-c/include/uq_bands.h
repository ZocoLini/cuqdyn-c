#ifndef UQ_BANDS_H
#define UQ_BANDS_H

#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

#include "cuqdyn.h"

/*
 * Prediction bands, built two different ways depending on whether a state is
 * measured. Both write into the same q_low / q_up matrices, sized m x n_states,
 * whose first row already holds the initial condition.
 *
 *   conformal_bands()  distribution-free, from the leave-one-out ensemble,
 *                      for the states the data measures
 *   delta_method_bands()  Gaussian propagation of the parameter covariance,
 *                      for the states that are never measured
 *
 * When every state is observed only the conformal path runs and the algorithm
 * reduces to the original CUQDyn1.
 */

/*
 * Conformal bands for the observed states.
 *
 *   lower(i,j) = quantile(ens_ij - resid_j, alp)
 *   upper(i,j) = quantile(ens_ij + resid_j, 1 - alp)
 *
 * ens_ij are the leave-one-out predictions at time i for state j and resid_j
 * the held-out absolute residuals of that observed state.
 *
 * media_matrix holds the m-1 leave-one-out trajectories, each n_states x m.
 * resid_loo is m x n_obs, with row 0 unused as the initial point is never
 * held out.
 */
void conformal_bands(MatrixArray media_matrix, SUNMatrix resid_loo, const int *observed_idx, int n_obs, double alp,
                     SUNMatrix q_low, SUNMatrix q_up);

/*
 * Delta-method bands for the states that are never measured.
 *
 *   Var[y_k(t)] = S_k(t) . Cov_p . S_k(t)'
 *   band = y_hat(t) +/- z_(1-alp) . sqrt(Var)
 *
 * The parameter covariance is the rank-aware FIM one, or the hybrid FIM-scale
 * plus LOO-correlation variant when the config selects it; the propagation is
 * identical either way.
 *
 * Sensitivities come from CVODES forward sensitivity analysis, which replaces
 * the complex-step differentiation of the Matlab toolbox: CVODES cannot
 * integrate in complex arithmetic but computes dy/dtheta natively, in a single
 * augmented integration.
 *
 * On success fills cov_p_out and std_y_out, which the caller owns. Returns 0.
 *
 * When the hybrid covariance is selected the plain FIM bands are computed too
 * and returned through q_low_alt_out / q_up_alt_out, so the two can be compared
 * on the same plot. The sensitivities are already in hand at that point, so the
 * second set costs one more quadratic form. Both are NULL otherwise.
 */
int delta_method_bands(N_Vector parameters, N_Vector initial_condition, sunrealtype t0, N_Vector times,
                       TransposedStates media_tot, ObservedData observed_data, const int *observed_idx, int n_obs,
                       SUNMatrix loo_params, SUNMatrix q_low, SUNMatrix q_up, SUNMatrix *cov_p_out,
                       SUNMatrix *std_y_out, SUNMatrix *q_low_alt_out, SUNMatrix *q_up_alt_out);

#endif // UQ_BANDS_H
