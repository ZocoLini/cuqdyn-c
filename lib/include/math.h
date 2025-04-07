//
// Created by borja on 03/04/25.
//

#ifndef MATH_H
#define MATH_H

#include <nvector/nvector_serial.h> /* access to serial N_Vector            */
#include <sunlinsol/sunlinsol_dense.h> /* access to dense SUNLinearSolver      */
#include <cvode/cvode.h>

typedef struct
{
    double *data;
    int x;
    int y;
    int z;
} Matrix3D;

Matrix3D create_matrix3d(int, int, int);
double get_matrix3d_value(Matrix3D, int, int, int);

typedef struct
{
    int number_eq;
    void *f;
    N_Vector initial_values;
    N_Vector times;
} ODEModel;

ODEModel create_ode_model(int number_eq, void *f, N_Vector initial_values, N_Vector times);

SUNMatrix solve_ode(N_Vector, ODEModel, SUNContext);

#endif // MATH_H
