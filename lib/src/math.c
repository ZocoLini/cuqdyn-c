//
// Created by borja on 03/04/25.
//

#include <cvode/cvode.h> /* prototypes for CVODE fcts., consts.  */
#include <lib.h>
#include <nvector/nvector_serial.h> /* access to serial N_Vector            */
#include <stdlib.h>
#include <sunlinsol/sunlinsol_dense.h> /* access to dense SUNLinearSolver      */
#include <sunmatrix/sunmatrix_dense.h> /* access to dense SUNMatrix            */


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

// TODO: This lines shouldn't be hardcoded
#define T0    SUN_RCONST(0.0)  /* initial time           */
#define Y1T0   SUN_RCONST(10.0) /* initial value of y1 */
#define Y2T0   SUN_RCONST(5.0) /* initial value of y2 */

#define RTOL  SUN_RCONST(1.0e-4) /* scalar relative tolerance            */
#define ATOL1 SUN_RCONST(1.0e-8) /* vector absolute tolerance components */
#define ATOL2 SUN_RCONST(1.0e-14)

/*
 * Solves the ODE system using the ode45 solver
 *
 * initial_values: data_matrix(1,2:end);
 * times: data_matrix(:,1);
 * parameters: constants to use in the ode
 */
SUNMatrix solve_ode(N_Vector initial_values, N_Vector times, N_Vector parameters, int number_eq, SUNContext sunctx, void *f)
{
    /* Set the vector absolute tolerance */ // Don't know if this is needed
    N_Vector abstol = N_VNew_Serial(number_eq, sunctx);
    Ith(abstol, 1) = ATOL1;
    Ith(abstol, 2) = ATOL2;

    void *cvode_mem = CVodeCreate(CV_BDF, sunctx);

    CVodeInit(cvode_mem, f, T0, initial_values);
    CVodeSVtolerances(cvode_mem, RTOL, abstol);
    CVodeSetUserData(cvode_mem, parameters);

    /* Create dense SUNMatrix for use in linear solves */
    SUNMatrix A = SUNDenseMatrix(number_eq, number_eq, sunctx);

    /* Create dense SUNLinearSolver object for use by CVode */
    SUNLinearSolver LS = SUNLinSol_Dense(times, A, sunctx);

    /* Attach the matrix and linear solver */
    CVodeSetLinearSolver(cvode_mem, LS, A);
}