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

ODEModel create_ode_model(int number_eq, void *f, N_Vector initial_values, N_Vector times)
{
    ODEModel ode_model;
    ode_model.f = f;
    ode_model.number_eq = number_eq;
    ode_model.initial_values = initial_values;
    ode_model.times = times;
    return ode_model;
}

// TODO: This lines shouldn't be hardcoded
#define RTOL  SUN_RCONST(1.0e-4) /* scalar relative tolerance            */
#define ATOL1 SUN_RCONST(1.0e-8) /* vector absolute tolerance components */
#define ATOL2 SUN_RCONST(1.0e-14)

static int check_retval(void*, const char*, int);

/*
 * Solves the ODE system using the ode45 solver
 *
 * initial_values: data_matrix(1,2:end);
 * times: data_matrix(:,1);
 * parameters: constants to use in the ode
 *
 * Returns:
 *   SUNMatrix where:
 *   - Each row corresponds to a time point
 *   - Column 0: Time values (t)
 *   - Columns 1-n: Solution components (y1, y2, ..., yn)
 *
 */
SUNMatrix solve_ode(N_Vector parameters, ODEModel ode_model, SUNContext sunctx)
{
    const sunrealtype t0 = N_VGetArrayPointer(ode_model.times)[0];               /* Initial time */

    /* Set the vector absolute tolerance */ // Don't know if this is needed
    N_Vector abstol = N_VNew_Serial(ode_model.number_eq, sunctx);
    Ith(abstol, 1) = ATOL1;
    Ith(abstol, 2) = ATOL2;

    void *cvode_mem = CVodeCreate(CV_ADAMS, sunctx);

    CVodeInit(cvode_mem, ode_model.f, t0, ode_model.initial_values);
    CVodeSVtolerances(cvode_mem, RTOL, abstol);
    CVodeSetUserData(cvode_mem, parameters);

    /* Create dense SUNMatrix for use in linear solves */
    SUNMatrix A = SUNDenseMatrix(ode_model.number_eq, ode_model.number_eq, sunctx);

    /* Create dense SUNLinearSolver object for use by CVode */
    SUNLinearSolver LS = SUNLinSol_Dense(ode_model.initial_values, A, sunctx);

    /* Attach the matrix and linear solver */
    CVodeSetLinearSolver(cvode_mem, LS, A);

    /* Time points */
    sunrealtype t;
    sunrealtype tinc = 0.1;
    sunrealtype tout = 3.5;
    const sunrealtype tf = 4.0;

    int retval;
    int retvalr;
    int rootsfound[2];
    sunrealtype *y_result = N_VGetArrayPointer(ode_model.initial_values);

    int result_rows = (tout - t0) / tinc;
    int result_cols = ode_model.number_eq + 1; // We add the time col
    SUNMatrix result = SUNDenseMatrix(result_rows, ode_model.number_eq, sunctx);
    sunrealtype *result_data = SM_DATA_D(result);

    int actual_result_matrix_row = 0;

    while (tout < tf)
    {
        retval = CVode(cvode_mem, tout, ode_model.initial_values, &t, CV_NORMAL);

        if (retval == CV_ROOT_RETURN)
        {
            retvalr = CVodeGetRootInfo(cvode_mem, rootsfound);
            if (check_retval(&retvalr, "CVodeGetRootInfo", 1)) { return NULL; }
        }

        if (check_retval(&retval, "CVode", 1)) { break; }
        if (retval == CV_SUCCESS)
        {
            tout += tinc;
        }

        // We are adding the time (t) as the first column but maybe we don't need it
        result_data[result_cols * actual_result_matrix_row] = t;

        for (int i = 0; i < ode_model.number_eq; i++) {
            result_data[result_cols * actual_result_matrix_row + i + 1] = y_result[i];
        }

        actual_result_matrix_row++;
    }

    return result;
}

int check_retval(void* returnvalue, const char* funcname, int opt)
{
    int* retval;

    /* Check if SUNDIALS function returned NULL pointer - no memory allocated */
    if (opt == 0 && returnvalue == NULL)
    {
        fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed - returned NULL pointer\n\n",
                funcname);
        return (1);
    }

    /* Check if retval < 0 */
    else if (opt == 1)
    {
        retval = (int*)returnvalue;
        if (*retval < 0)
        {
            fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed with retval = %d\n\n",
                    funcname, *retval);
            return (1);
        }
    }

    /* Check if function returned NULL pointer - no memory allocated */
    else if (opt == 2 && returnvalue == NULL)
    {
        fprintf(stderr, "\nMEMORY_ERROR: %s() failed - returned NULL pointer\n\n",
                funcname);
        return (1);
    }

    return (0);
}