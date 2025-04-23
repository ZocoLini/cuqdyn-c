#ifndef LIB_H
#define LIB_H

#include <stdlib.h>
#include <sundials_old/sundials_nvector.h>

#include "ode_solver.h"

#define SM_ROWS_D(mat) mat->M
#define SM_COLUMNS_D(mat) mat->N
#define SUNDenseMatrix(m, n, ctx) NewDenseMat(m, n)
#define SM_ELEMENT_D(mat, i, j) DENSE_ELEM(mat, i, j)
#define N_VNew_Serial(n, ctx) N_VNew_Serial(n)
#define SM_DATA_D(mat) mat->data
#define SUNMatDestroy(mat) DestroyMat(mat)
#define SUN_RCONST(n) n
#define N_VGetLength_Serial(v) NV_LENGTH_S(v)

#define Ith(v, i) NV_Ith_S(v, i - 1) /* i-th vector component i=1..n */
#define IJth(A, i, j) SM_ELEMENT_D(A, i - 1, j - 1) /* (i,j)-th matrix component i,j=1..n */

// function

typedef enum
{
    LOTKA_VOLTERRA = 0,
    ALPHA_PINENE = 1,
    LOGISTIC = 2
} FunctionType;

typedef struct
{
    FunctionType function_type;
    N_Vector lower_bounds;
    N_Vector upper_bounds;
    N_Vector parameters;
} Problem;

Problem create_problem(FunctionType, N_Vector, N_Vector, N_Vector);

typedef struct
{
    int max_iterations;
    double *log_var_index;
    int should_save;
    char solver[5];
} Options;

Options create_options(int, double *, int, char[5]);

typedef struct
{
    N_Vector best;
} Results;

Results ess_solver(Problem, Options, N_Vector, DlsMat);
void predict_parameters(N_Vector, DlsMat, ODEModel, TimeConstraints, Tolerances);

typedef struct
{
    long *data;
    long len;
} LongArray;

LongArray create_array(long *, long);
LongArray create_empty_array();
long array_get_index(LongArray, long);

typedef struct
{
    DlsMat *data;
    long len;
} MatrixArray;

MatrixArray create_matrix_array(long);
void destroy_matrix_array(MatrixArray array);
DlsMat matrix_array_get_index(MatrixArray, long);
void matrix_array_set_index(MatrixArray, long, DlsMat);
DlsMat matrix_array_get_median(MatrixArray);
N_Vector matrix_array_depth_vector_at(MatrixArray, long i, long j);

N_Vector get_matrix_cols_median(DlsMat);

#endif // LIB_H
