#ifndef CUQDYN_H
#define CUQDYN_H

#include <sundials_old/sundials_nvector.h>

#include "ode_solver.h"

#define SM_ROWS_D(mat) mat->M
#define SM_COLUMNS_D(mat) mat->N
#define SUNDenseMatrix(m, n) NewDenseMat(m, n)
#define SM_ELEMENT_D(mat, i, j) DENSE_ELEM(mat, i, j)
#define SM_DATA_D(mat) mat->data
#define SUNMatDestroy(mat) DestroyMat(mat)

#define MIth(v, i) NV_Ith_S(v, i - 1) /* i-th vector component i=1..n */
#define MIJth(A, i, j) SM_ELEMENT_D(A, i - 1, j - 1) /* (i,j)-th matrix component i,j=1..n */

/// Result of the cuqdyn algorithm
typedef struct
{
    DlsMat predicted_data_median;
    N_Vector predicted_params_median;
    DlsMat q_low;
    DlsMat q_up;
    N_Vector times;
} CuqdynResult;

CuqdynResult* create_cuqdyn_result(DlsMat predicted_data_median, N_Vector predicted_params_median,
    DlsMat q_low, DlsMat q_up, N_Vector times);
void destroy_cuqdyn_result(CuqdynResult* result);
CuqdynResult *cuqdyn_algo(const char *data_file, const char *sacess_conf_file, const char *output_file, int rank, int nproc);

typedef struct
{
    long *data;
    long len;
} LongArray;

LongArray create_array(long * values, long len);
LongArray create_empty_array();
long array_get_index(LongArray array, long index);

typedef struct
{
    DlsMat *data;
    long len;
} MatrixArray;

MatrixArray create_matrix_array(long depth);
void destroy_matrix_array(MatrixArray array);
DlsMat matrix_array_get_index(MatrixArray array, long index);
/// Sets the i-th matrix of the array
void matrix_array_set_index(MatrixArray array, long index, DlsMat matrix);
/// Returns a matrix where the i-th row and j-th column is the median
/// of all the i-th row and j-th column of the matrices inside the array
DlsMat matrix_array_get_median(MatrixArray array);
/// Resturns a vector containing the i-th row and j-th column of each matrix inside the array
N_Vector matrix_array_depth_vector_at(MatrixArray array, long i, long j);

/// Creates a vector where the i-th element is the median of the i-th column of the matrix
N_Vector get_matrix_cols_median(DlsMat matrix);

#endif // CUQDYN_H
