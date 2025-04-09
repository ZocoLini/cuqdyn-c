#ifndef LIB_H
#define LIB_H

#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>
#include "ode_solver.h"


#define Ith(v, i) NV_Ith_S(v, i - 1) /* i-th vector component i=1..n */
#define IJth(A, i, j) SM_ELEMENT_D(A, i - 1, j - 1) /* (i,j)-th matrix component i,j=1..n */

// function

SUNContext get_sun_context();

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

Results meigo(Problem, Options, N_Vector, SUNMatrix);
void predict_parameters(N_Vector, SUNMatrix, ODEModel, TimeConstraints, Tolerances);

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
    SUNMatrix *data;
    long len;
} MatrixArray;

MatrixArray create_matrix_array(long);
SUNMatrix matrix_array_get_index(MatrixArray, long);
void matrix_array_set_index(MatrixArray, long, SUNMatrix);
SUNMatrix matrix_array_get_median(MatrixArray);

N_Vector get_matrix_cols_median(SUNMatrix);

#endif // LIB_H
