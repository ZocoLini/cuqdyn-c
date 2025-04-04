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
    double *lower_bounds;
    double *upper_bounds;
    double *parameters;
};

struct Problem create_problem(enum FunctionType, double *, double *, double *);

struct Options
{
    int max_iterations;
    double *log_var_index;
    int should_save;
    char solver[];
};

struct Options create_options(int, double *, int, char[]);

struct Results
{
    struct Vector best;
};

struct Results meigo(struct Problem, struct Options, struct Vector, struct Matrix);

void prob_mod_dynamics_ap(double*, double*, double*);
void prob_mod_dynamics_log(double*, double*, double*);
void prob_mod_dynamics_lv(double*, double*, double*);

#endif //LIB_H
