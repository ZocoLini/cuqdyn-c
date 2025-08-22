#include <config.h>
#include <cvodes/cvodes.h>
#include <functions.h>
#include <ode_solver.h>
#include <string.h>
#include <sunlinsol/sunlinsol_dense.h>
#include <sunmatrix/sunmatrix_dense.h>
#include <sunmatrix/sunmatrix_sparse.h>

#include "cuqdyn.h"
#include "cvodes/cvodes_ls.h"
#include "sundials/sundials_types.h"

#ifndef JE
#define JE(J,i,j) SM_ELEMENT_D((J),(i),(j))
#endif

static int check_retval(void *, const char *, int);

int nfk_jac(sunrealtype t, N_Vector y, N_Vector fy,
                       SUNMatrix J, void *user_data,
                       N_Vector tmp1, N_Vector tmp2, N_Vector tmp3)
{
    (void)t; (void)fy; (void)tmp1; (void)tmp2; (void)tmp3;
    
        const sunrealtype *Y = NV_DATA_S(y);
        const sunrealtype y1=Y[0], y2=Y[1], y3=Y[2], y4=Y[3], y5=Y[4],
                       y6=Y[5], y7=Y[6], y8=Y[7], y9=Y[8], y10=Y[9],
                       y11=Y[10], y12=Y[11], y13=Y[12], y14=Y[13], y15=Y[14];
    
        const sunrealtype *p = (const sunrealtype*) user_data;
        const sunrealtype p1 = p[0],  p2 = p[1],  p3 = p[2],  p4 = p[3],  p5 = p[4],
                       p6 = p[5],  p7 = p[6],  p8 = p[7],  p9 = p[8],  p10= p[9],
                       p11= p[10], p12= p[11], p13= p[12], p14= p[13], p15= p[14],
                       p16= p[15], p17= p[16], p18= p[17], p19= p[18], p20= p[19],
                       p21= p[20], p22= p[21], p23= p[22], p24= p[23], p25= p[24],
                       p26= p[25], p27= p[26], p28= p[27], p29= p[28];
    
        // Limpia la matriz (si tu versión de SUNDIALS no garantiza cero)
        for (int j = 0; j < SM_COLUMNS_D(J); ++j) 
        {
            for (int i = 0; i < SM_ROWS_D(J); ++i) 
            {
                SM_ELEMENT_D(J,i,j) = 0.0;
            }
        }
    
        // f1
        JE(J, 0, 0) = -p21 -p17;
        
        // f2
        JE(J, 1, 0) = p17;
        JE(J, 1, 1) = -p19 - p18*y8 - p21 - p2*y10 - p4*y13;
        JE(J, 1, 3) = p3;
        JE(J, 1, 4) = p5;
        JE(J, 1, 7) = -p18*y2;
        JE(J, 1, 9) = -p2*y2;
        JE(J, 1, 12) = -p4*y2;
        
        // f3
        JE(J, 2, 1) = p19 + p18*y8;
        JE(J, 2, 2) = -p21;
        JE(J, 2, 7) = p18*y2;
    
        // f4
        JE(J, 3, 1) = p2*y10;
        JE(J, 3, 3) = -p3;
        JE(J, 3, 9) = p2*y2;
        
        // f5
        JE(J, 4, 1) = p4*y13;
        JE(J, 4, 4) = -p5;
        JE(J, 4, 12) = p4*y2;
        
        // f6
        JE(J, 5, 4) = p5;
        JE(J, 5, 5) = -p1*y10 -p23;
        JE(J, 5, 9) = -p1*y6;
        JE(J, 5, 12) = p11;
        
        // f7
        JE(J, 6, 5) = p23*p22;
        JE(J, 6, 6) = -p1*y11;
        JE(J, 6, 10) = -p1*y7;
        
        // f8
        JE(J, 7, 7) = -p16;
        JE(J, 7, 8) = p15;
        
        // f9
        JE(J, 8, 6) = p12; 
        JE(J, 8, 8) = -p14;
        
        // f10
        JE(J, 9, 1) = -p2*y10;
        JE(J, 9, 5) = -p1*y10;
        JE(J, 9, 9) = -p2*y2 - p1*y6 - p10 - p25;
        JE(J, 9, 10) = p26;
        JE(J, 9, 11) = p9;
        
        // f11
        JE(J, 10, 6) = -p1*y11; 
        JE(J, 10, 9) = p25*p22; 
        JE(J, 10, 10) = -p1*y7 - p26*p22; 
        
        // f12
        JE(J, 11, 6) = p6;
        JE(J, 11, 11) = -p8;
        
        // f13
        JE(J, 12, 1) = -p4*y13; 
        JE(J, 12, 5) = p1*y10;
        JE(J, 12, 9) = p1*y6;
        JE(J, 12, 12) = -p11 -p4*y2;
        JE(J, 12, 13) = p24;
        
        // f14
        JE(J, 13, 6) = p1*y11; 
        JE(J, 13, 10) = p1*y7;
        JE(J, 13, 13) = -p24*p22;
        
        // f15
        JE(J, 14, 6) = p27;
        JE(J, 14, 14) = -p29;
        
        return 0; // éxito
}


TransposedStates solve_ode(N_Vector parameters, N_Vector initial_values, sunrealtype t0, N_Vector times)
{
    CuqdynConf *cuqdyn_conf = get_cuqdyn_conf(get_cuqdyn_context());
    Tolerances tolerances = cuqdyn_conf->tolerances;

    int retval;
    void *cvode_mem = CVodeCreate(CV_BDF, get_sundials_ctx());
    if (check_retval((void *) cvode_mem, "CVodeCreate", 0))
    {
        return NULL;
    }

    retval = CVodeInit(cvode_mem, ode_model_fun, t0, initial_values);
    if (check_retval(&retval, "CVodeInit", 1))
    {
        return NULL;
    }

    N_Vector cloned_abs_tol = New_Serial(tolerances.atol_len);
    memcpy(NV_DATA_S(cloned_abs_tol), tolerances.atol, tolerances.atol_len * sizeof(sunrealtype));

    // We clone the tolerances because the CVodeFree function frees the memory allocated for the abs_tol it receives
    retval = CVodeSVtolerances(cvode_mem, tolerances.rtol, cloned_abs_tol);
    if (check_retval(&retval, "CVodeSVtolerances", 1))
    {
        return NULL;
    }

    retval = CVodeSetUserData(cvode_mem, parameters);
    if (check_retval(&retval, "CVodeSetUserData", 1))
    {
        return NULL;
    }

    SUNMatrix A = NewDenseMatrix(cuqdyn_conf->ode_expr.y_count, cuqdyn_conf->ode_expr.y_count);
    SUNLinearSolver LS = SUNLinSol_Dense(initial_values, A, get_sundials_ctx());
    retval = CVodeSetLinearSolver(cvode_mem, LS, A);
    if (check_retval(&retval, "CVodeSetLinearSolver", 1))
    {
        return NULL;
    }

    retval = CVodeSetJacFn(cvode_mem, nfk_jac);
    if (check_retval(&retval, "CVodeSetJacFn", 1))
    {
        return NULL;
    }
    
    retval = CVodeSetMaxOrd(cvode_mem, 1);
    if (check_retval(&retval, "CVodeSetMaxOrd", 1))
    {
        return NULL;
    }
    
    retval = CVodeSetMaxNumSteps(cvode_mem, 1000000);
    if (check_retval(&retval, "CVodeSetMaxNumSteps", 1))
    {
        return NULL;
    }

    /* Time points */
    sunrealtype t;

    N_Vector yout = New_Serial(NV_LENGTH_S(initial_values));
    int result_rows = cuqdyn_conf->ode_expr.y_count;
    TransposedStates result = NewDenseMatrix(result_rows, NV_LENGTH_S(times));

    for (int i = 0; i < NV_LENGTH_S(times); ++i)
    {
        const sunrealtype actual_time = NV_Ith_S(times, i);

        if (actual_time == t0)
        {
            memcpy(SM_COLUMN_D(result, i), NV_DATA_S(initial_values),
                   NV_LENGTH_S(initial_values) * sizeof(sunrealtype));
            continue;
        }

        retval = CVode(cvode_mem, actual_time, yout, &t, CV_NORMAL);

        if (check_retval(&retval, "CVode", 1))
        {
            return NULL;
        }

        memcpy(SM_COLUMN_D(result, i), NV_DATA_S(yout), NV_LENGTH_S(yout) * sizeof(sunrealtype));
    }

    N_VDestroy(yout);
    CVodeFree(&cvode_mem);

    return result;
}

int check_retval(void *returnvalue, const char *funcname, int opt)
{
    /* Check if SUNDIALS function returned NULL pointer - no memory allocated */
    if (opt == 0 && returnvalue == NULL)
    {
        fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed - returned NULL pointer\n\n", funcname);
        return (1);
    }

    if (opt == 1)
    {
        int *retval = returnvalue;
        if (*retval < 0)
        {
            fprintf(stderr, "\nSUNDIALS_ERROR: %s() failed with retval = %d\n\n", funcname, *retval);
            return (1);
        }
    }

    return (0);
}
