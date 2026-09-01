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
 * What one parameter covariance produces.
 *
 * Prediction bands cover every state. The ones the data measures get
 * distribution-free conformal bands from the leave-one-out ensemble, and the
 * ones it never measures get Gaussian delta-method bands propagated from the
 * covariance. Only the second kind depends on which covariance this is, so with
 * every state observed the two varieties below hold the same numbers and the
 * result matches the original CUQDyn1.
 */
typedef struct
{
    /// Prediction bands, m x n_states, row 0 the initial condition.
    SUNMatrix q_low;
    SUNMatrix q_up;
    /// Parameter covariance in natural units, n_params x n_params. NULL when it
    /// could not be built, which leaves the bands conformal-only.
    SUNMatrix cov_p;
    /// Delta-method standard deviations, n_states x m, or NULL as above.
    SUNMatrix std_y;
} UqBands;

/*
 * Result of the CUQDyn1_Plus algorithm.
 *
 * Both covariance varieties are always produced, so a run answers which one to
 * trust rather than being told up front.
 */
typedef struct
{
    TransposedStates predicted_data_median;
    N_Vector predicted_params_median;
    /// Rank-aware FIM covariance, as CUQDyn1_Plus propagates it.
    UqBands fim;
    /// FIM marginal scale with the correlation structure of the leave-one-out
    /// ensemble, as CUQDyn1_Plus_HybridCov propagates it.
    UqBands hybrid;
    N_Vector times;

    /// Best-fit trajectory from the full-data fit, n_states x m.
    TransposedStates media_tot;
    /// Best-fit parameters from the full-data fit.
    N_Vector parameters_init;
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
