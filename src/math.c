//
// Created by borja on 03/04/25.
//

#include <stdlib.h>
#include <cvode/cvode.h>

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

/*
 * Solves the ODE system using the ode45 solver
 *
 * initial_values: data_matrix(1,2:end);
 * times: data_matrix(:,1);
 * parameters: Result from meigo ESS in the original code
 */
SUNMatrix solve_ode(N_Vector initial_values, N_Vector times, N_Vector parameters)
{

}
