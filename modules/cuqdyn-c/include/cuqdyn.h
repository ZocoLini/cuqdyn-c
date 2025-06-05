#ifndef CUQDYN_H
#define CUQDYN_H

#include <sundials/sundials_nvector.h>

#include "ode_solver.h"

#define NewDenseMatrix(m, n) SUNDenseMatrix(m, n, get_sundials_ctx())
#define New_Serial(n) N_VNew_Serial(n, get_sundials_ctx())

SUNContext get_sundials_ctx();

/// Result of the cuqdyn algorithm
typedef struct
{
    SUNMatrix predicted_data_median;
    N_Vector predicted_params_median;
    SUNMatrix q_low;
    SUNMatrix q_up;
    N_Vector times;
} CuqdynResult;

CuqdynResult* create_cuqdyn_result(SUNMatrix predicted_data_median, N_Vector predicted_params_median,
    SUNMatrix q_low, SUNMatrix q_up, N_Vector times);
void destroy_cuqdyn_result(CuqdynResult* result);
CuqdynResult *cuqdyn_algo(const char *data_file, const char *sacess_conf_file, const char *output_file);

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
