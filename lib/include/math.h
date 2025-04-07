//
// Created by borja on 03/04/25.
//

#ifndef MATH_H
#define MATH_H

typedef struct
{
    double *data;
    int x;
    int y;
    int z;
} Matrix3D;

Matrix3D create_matrix3d(int, int, int);
double get_matrix3d_value(Matrix3D, int, int, int);

#endif // MATH_H
