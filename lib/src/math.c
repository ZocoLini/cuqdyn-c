//
// Created by borja on 03/04/25.
//

#include <cvode/cvode.h> /* prototypes for CVODE fcts., consts.  */
#include <lib.h>
#include <nvector/nvector_serial.h> /* access to serial N_Vector            */
#include <stdlib.h>
#include <sunlinsol/sunlinsol_dense.h> /* access to dense SUNLinearSolver      */
#include <sunmatrix/sunmatrix_dense.h> /* access to dense SUNMatrix            */
#include <time.h>


Matrix3D create_matrix3d(const int x, const int y, const int z)
{
    Matrix3D matrix;
    matrix.x = x;
    matrix.y = y;
    matrix.z = z;
    matrix.data = (double *) malloc(x * y * z * sizeof(double));
    return matrix;
}

double get_matrix3d_value(const Matrix3D matrix, const int x, const int y, const int z)
{
    return matrix.data[x * matrix.y * matrix.z + y * matrix.z + z]; // Unchecked
}
