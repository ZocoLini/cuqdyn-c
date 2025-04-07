//
// Created by borja on 03/04/25.
//

#ifndef LIB_H
#define LIB_H

#include "math.h"

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

Results meigo(Problem, Options, N_Vector, SUNMatrix);

void prob_mod_dynamics_ap(double *, double *, double *);
void prob_mod_dynamics_log(double *, double *, double *);
void prob_mod_dynamics_lv(double *, double *, double *);

typedef struct
{
    long *data;
    long len;
} Array;

Array create_array(long *, long);
Array create_empty_array();
long array_get_index(Array, long);

#endif // LIB_H
