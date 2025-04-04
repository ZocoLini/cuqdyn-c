//
// Created by borja on 03/04/25.
//

#ifndef MATH_H
#define MATH_H

struct Matrix
{
    double *data;
    int rows;
    int cols;
};

struct Matrix create_matrix(int, int);
double get_matrix_value(struct Matrix, int, int);

struct Matrix3D
{
    double *data;
    int x;
    int y;
    int z;
};

struct Matrix3D create_matrix3d(int, int, int);
double get_matrix3d_value(struct Matrix3D, int, int, int);

struct Vector
{
    double *data;
    int len;
    int capacity;
};

struct Vector create_vector(int);
double get_vector_value(struct Vector, int);

struct Matrix solve_ode(struct Vector, struct Vector, struct Vector);

#endif // MATH_H
