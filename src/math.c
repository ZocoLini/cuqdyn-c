//
// Created by borja on 03/04/25.
//

#include <stdlib.h>
#include <cvode/cvode.h>
#include <sunmatrix/sunmatrix_dense.h>
#include <nvector/nvector_serial.h>
#include <sundials/sundials_types.h>

struct Matrix
{
    double *data;
    int rows;
    int cols;
};

struct Matrix new_matrix(const int rows, const int cols)
{
    struct Matrix matrix;
    matrix.rows = rows;
    matrix.cols = cols;
    matrix.data = (double *) malloc(rows * cols * sizeof(double));
    return matrix;
}

double get_matrix_value(const struct Matrix matrix, const int row, const int col)
{
    return matrix.data[row * matrix.cols + col];
}

struct Matrix3D
{
    double *data;
    int x;
    int y;
    int z;
};

struct Matrix3D create_matrix3d(const int x, const int y, const int z)
{
    struct Matrix3D matrix;
    matrix.x = x;
    matrix.y = y;
    matrix.z = z;
    matrix.data = (double *) malloc(x * y * z * sizeof(double));
    return matrix;
}

double get_matrix3d_value(const struct Matrix3D matrix, const int x, const int y, const int z)
{
    return matrix.data[x * matrix.y * matrix.z + y * matrix.z + z]; // Unchecked
}

struct Vector
{
    double *data;
    int len;
    int capacity;
};

struct Vector new_vector(const int capacity)
{
    struct Vector vector;
    vector.len = 0;
    vector.capacity = capacity;
    vector.data = (double *) malloc(capacity * sizeof(double));
    return vector;
}

/*
 * Solves the ODE system using the ode45 solver
 *
 * initial_values: data_matrix(1,2:end);
 * times: data_matrix(:,1);
 * parameters: Result from meigo ESS in the original code
 */
struct Matrix solve_ode(struct Vector initial_values, struct Vector times, struct Vector parameters)
{

}
