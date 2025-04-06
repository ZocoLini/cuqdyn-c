//
// Created by borja on 03/04/25.
//

#ifndef MATH_H
#define MATH_H

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

typedef struct
{
    double *data;
    int x;
    int y;
    int z;
} Matrix3D;

Matrix3D create_matrix3d(int, int, int);
double get_matrix3d_value(Matrix3D, int, int, int);

SUNMatrix solve_ode(N_Vector, N_Vector, N_Vector);

#endif // MATH_H
