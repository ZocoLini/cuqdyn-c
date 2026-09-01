#ifndef UQ_BANDS_H
#define UQ_BANDS_H

#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

#include "cuqdyn.h"

/*
 * Prediction bands, built two different ways depending on whether a state is
 * measured.
 *
 *   conformal_bands()  distribution-free, from the leave-one-out ensemble,
 *                      for the states the data measures
 *   delta_method_bands()  Gaussian propagation of the parameter covariance,
 *                      for the states that are never measured
 *
 * conformal_bands() writes the base pair, sized m x n_states, whose first row
 * already holds the initial condition. delta_method_bands() copies that base
 * once per covariance variety and rewrites the hidden states in each.
 *
 * When every state is observed only the conformal path has anything to say and
 * the algorithm reduces to the original CUQDyn1.
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
 * Delta-method bands for the states that are never measured, both varieties.
 *
 *   Var[y_k(t)] = S_k(t) . Cov_p . S_k(t)'
 *   band = y_hat(t) +/- z_(1-alp) . sqrt(Var)
 *
 * Cov_p is built twice: the rank-aware FIM covariance, and the hybrid variant
 * that keeps its marginal scale but takes the correlation structure from the
 * LOO ensemble. The propagation is identical either way, and the sensitivities
 * are shared, so the second variety costs one more quadratic form.
 *
 * Sensitivities come from CVODES forward sensitivity analysis, which replaces
 * the complex-step differentiation of the Matlab toolbox: CVODES cannot
 * integrate in complex arithmetic but computes dy/dtheta natively, in a single
 * augmented integration.
 *
 * q_low_base and q_up_base are the conformal bands: row 0 the initial condition
 * and the measured states already covered. Each variety starts as a copy and
 * has only its hidden states rewritten, so the two agree wherever the
 * covariance has no say.
 *
 * fim_out and hybrid_out are filled before anything that can fail, and the
 * caller owns all four matrices in each whether this returns 0 or not. A
 * non-zero return means one of them kept the conformal base, with its cov_p and
 * std_y left NULL.
 */
int delta_method_bands(N_Vector parameters, N_Vector initial_condition, sunrealtype t0, N_Vector times,
                       TransposedStates media_tot, ObservedData observed_data, const int *observed_idx, int n_obs,
                       SUNMatrix loo_params, SUNMatrix q_low_base, SUNMatrix q_up_base, UqBands *fim_out,
                       UqBands *hybrid_out);

/*
 * Both varieties as the conformal base alone, with no covariance propagated:
 * what a run has to fall back on when the best-fit trajectory is missing and
 * there is nothing to take sensitivities from. delta_method_bands starts here
 * too, before its first fallible step.
 */
void conformal_only_bands(SUNMatrix q_low_base, SUNMatrix q_up_base, long m, long n_states, UqBands *fim_out,
                          UqBands *hybrid_out);

/// Releases what delta_method_bands filled in.
void destroy_uq_bands(UqBands *bands);

#endif // UQ_BANDS_H
