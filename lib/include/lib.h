//
// Created by borja on 03/04/25.
//

#ifndef LIB_H
#define LIB_H

#include "math.h"

// function

enum FunctionType
{
    LOTKA_VOLTERRA = 0,
    ALPHA_PINENE = 1,
    LOGISTIC = 2
};

struct Problem
{
    enum FunctionType function_type;
    N_Vector lower_bounds;
    N_Vector upper_bounds;
    N_Vector parameters;
};

struct Problem create_problem(enum FunctionType, N_Vector, N_Vector, N_Vector);

struct Options
{
    int max_iterations;
    double *log_var_index;
    int should_save;
    char solver[5];
};

struct Options create_options(int, double *, int, char[5]);

struct Results
{
    N_Vector best;
};

struct Results meigo(struct Problem, struct Options, N_Vector, SUNMatrix);

void prob_mod_dynamics_ap(double*, double*, double*);
void prob_mod_dynamics_log(double*, double*, double*);
void prob_mod_dynamics_lv(double*, double*, double*);

#endif //LIB_H
