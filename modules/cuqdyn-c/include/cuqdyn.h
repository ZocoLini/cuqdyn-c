#ifndef CUQDYN_H
#define CUQDYN_H

#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

#define NewDenseMatrix(m, n) SUNDenseMatrix(m, n, get_sundials_ctx())
#define New_Serial(n) N_VNew_Serial(n, get_sundials_ctx())

typedef SUNMatrix States;
/*
 *   TransposedStates where:
 *   - Each col corresponds to a time point
 *   - Rows 0-n: Solution components (y1, y2, ..., yn)
 */
typedef SUNMatrix TransposedStates;
typedef SUNMatrix ObservablesStates;
typedef SUNMatrix ObservablesTransposedStates;
typedef SUNMatrix ObservedData;
typedef SUNMatrix TransposedObservedData;

SUNContext get_sundials_ctx();

/*
 * Result of the CUQDyn1_Plus algorithm.
 *
 * q_low/q_up hold the prediction bands for every state. Observed states get
 * distribution-free conformal bands from the leave-one-out ensemble; states
 * that are never measured get Gaussian delta-method bands propagated from the
 * parameter covariance. When every state is observed the Gaussian branch is
 * skipped entirely and the result matches the original CUQDyn1.
 */
typedef struct
{
    TransposedStates predicted_data_median;
    N_Vector predicted_params_median;
    SUNMatrix q_low;
    SUNMatrix q_up;
    N_Vector times;

    /// Best-fit trajectory from the full-data fit, n_states x m.
    TransposedStates media_tot;
    /// Best-fit parameters from the full-data fit.
    N_Vector parameters_init;
    /// Parameter covariance in natural units, or NULL when every state is observed.
    SUNMatrix cov_p;
    /// Delta-method standard deviations, n_states x m, or NULL as above.
    SUNMatrix std_y;
    /// Plain FIM bands, filled only when the hybrid covariance was used, so the
    /// two can be compared. NULL otherwise.
    SUNMatrix q_low_alt;
    SUNMatrix q_up_alt;
    /// Leave-one-out parameter estimates, (m-1) x n_params.
    SUNMatrix loo_params;
    /// Held-out absolute residuals, (m-1) x n_obs.
    SUNMatrix resid_loo;

    /// 0-based indices of the measured states, length n_obs.
    int *observed_idx;
    int n_obs;
    long n_states;
} CuqdynResult;

CuqdynResult *create_cuqdyn_result(void);
void destroy_cuqdyn_result(CuqdynResult *result);
CuqdynResult *cuqdyn_algo(const char *data_file, const char *sacess_conf_file, const char *output_file);

typedef struct
{
    long *data;
    long len;
} LongArray;

LongArray create_array(long *values, long len);
LongArray create_empty_array();
long array_get_index(LongArray array, long index);

typedef struct
{
    SUNMatrix *data;
    long len;
} MatrixArray;

MatrixArray create_matrix_array(long depth);
void destroy_matrix_array(MatrixArray array);
SUNMatrix matrix_array_get_index(MatrixArray array, long index);
/// Sets the i-th matrix of the array
void matrix_array_set_index(MatrixArray array, long index, SUNMatrix matrix);
/// Returns a matrix where the i-th row and j-th column is the median
/// of all the i-th row and j-th column of the matrices inside the array
SUNMatrix matrix_array_get_median(MatrixArray array);
/// Resturns a vector containing the i-th row and j-th column of each matrix inside the array
N_Vector matrix_array_depth_vector_at(MatrixArray array, long i, long j);

/// Creates a vector where the i-th element is the median of the i-th column of the matrix
N_Vector get_matrix_cols_median(SUNMatrix matrix);

#endif // CUQDYN_H
