/*
 * -----------------------------------------------------------------
 * $Revision: 1.8 $
 * $Date: 2010/12/01 22:17:18 $
 * -----------------------------------------------------------------
 * Programmer: Radu Serban @ LLNL
 * -----------------------------------------------------------------
 * Copyright (c) 2006, The Regents of the University of California.
 * Produced at the Lawrence Livermore National Laboratory.
 * All rights reserved.
 * For details, see the LICENSE file.
 * -----------------------------------------------------------------
 * This is the header file for a generic package of DENSE matrix
 * operations, based on the SUNMatrix type defined in sundials_direct.h.
 *
 * There are two sets of dense solver routines listed in
 * this file: one set uses type SUNMatrix defined below and the
 * other set uses the type sunrealtype ** for dense matrix arguments.
 * Routines that work with the type SUNMatrix begin with "Dense".
 * Routines that work with sunrealtype** begin with "dense".
 * -----------------------------------------------------------------
 */

#ifndef _SUNDIALS_DENSE_H
#define _SUNDIALS_DENSE_H

#ifdef __cplusplus  /* wrapper to enable C++ usage */
extern "C" {
#endif

#include <sundials/sundials_direct.h>

/*
 * -----------------------------------------------------------------
 * Functions: DenseGETRF and DenseGETRS
 * -----------------------------------------------------------------
 * DenseGETRF performs the LU factorization of the M by N dense
 * matrix A. This is done using standard Gaussian elimination
 * with partial (row) pivoting. Note that this applies only
 * to matrices with M >= N and full column rank.
 *
 * A successful LU factorization leaves the matrix A and the
 * pivot array p with the following information:
 *
 * (1) p[k] contains the row number of the pivot element chosen
 *     at the beginning of elimination step k, k=0, 1, ..., N-1.
 *
 * (2) If the unique LU factorization of A is given by PA = LU,
 *     where P is a permutation matrix, L is a lower trapezoidal
 *     matrix with all 1's on the diagonal, and U is an upper
 *     triangular matrix, then the upper triangular part of A
 *     (including its diagonal) contains U and the strictly lower
 *     trapezoidal part of A contains the multipliers, I-L.
 *
 * For square matrices (M=N), L is unit lower triangular.
 *
 * DenseGETRF returns 0 if successful. Otherwise it encountered
 * a zero diagonal element during the factorization. In this case
 * it returns the column index (numbered from one) at which
 * it encountered the zero.
 *
 * DenseGETRS solves the N-dimensional system A x = b using
 * the LU factorization in A and the pivot information in p
 * computed in DenseGETRF. The solution x is returned in b. This
 * routine cannot fail if the corresponding call to DenseGETRF
 * did not fail.
 * DenseGETRS does NOT check for a square matrix!
 *
 * -----------------------------------------------------------------
 * DenseGETRF and DenseGETRS are simply wrappers around denseGETRF
 * and denseGETRS, respectively, which perform all the work by
 * directly accessing the data in the SUNMatrix A (i.e. the field cols)
 * -----------------------------------------------------------------
 */

SUNDIALS_EXPORT long int DenseGETRF(SUNMatrix A, long int *p);
SUNDIALS_EXPORT void DenseGETRS(SUNMatrix A, long int *p, sunrealtype *b);

SUNDIALS_EXPORT long int denseGETRF(sunrealtype **a, long int m, long int n, long int *p);
SUNDIALS_EXPORT void denseGETRS(sunrealtype **a, long int n, long int *p, sunrealtype *b);

/*
 * -----------------------------------------------------------------
 * Functions : DensePOTRF and DensePOTRS
 * -----------------------------------------------------------------
 * DensePOTRF computes the Cholesky factorization of a real symmetric
 * positive definite matrix A.
 * -----------------------------------------------------------------
 * DensePOTRS solves a system of linear equations A*X = B with a 
 * symmetric positive definite matrix A using the Cholesky factorization
 * A = L*L**T computed by DensePOTRF.
 *
 * -----------------------------------------------------------------
 * DensePOTRF and DensePOTRS are simply wrappers around densePOTRF
 * and densePOTRS, respectively, which perform all the work by
 * directly accessing the data in the SUNMatrix A (i.e. the field cols)
 * -----------------------------------------------------------------
 */

SUNDIALS_EXPORT long int DensePOTRF(SUNMatrix A);
SUNDIALS_EXPORT void DensePOTRS(SUNMatrix A, sunrealtype *b);

SUNDIALS_EXPORT long int densePOTRF(sunrealtype **a, long int m);
SUNDIALS_EXPORT void densePOTRS(sunrealtype **a, long int m, sunrealtype *b);

/*
 * -----------------------------------------------------------------
 * Functions : DenseGEQRF and DenseORMQR
 * -----------------------------------------------------------------
 * DenseGEQRF computes a QR factorization of a real M-by-N matrix A:
 * A = Q * R (with M>= N).
 * 
 * DenseGEQRF requires a temporary work vector wrk of length M.
 * -----------------------------------------------------------------
 * DenseORMQR computes the product w = Q * v where Q is a real 
 * orthogonal matrix defined as the product of k elementary reflectors
 *
 *        Q = H(1) H(2) . . . H(k)
 *
 * as returned by DenseGEQRF. Q is an M-by-N matrix, v is a vector
 * of length N and w is a vector of length M (with M>=N).
 *
 * DenseORMQR requires a temporary work vector wrk of length M.
 *
 * -----------------------------------------------------------------
 * DenseGEQRF and DenseORMQR are simply wrappers around denseGEQRF
 * and denseORMQR, respectively, which perform all the work by
 * directly accessing the data in the SUNMatrix A (i.e. the field cols)
 * -----------------------------------------------------------------
 */

SUNDIALS_EXPORT int DenseGEQRF(SUNMatrix A, sunrealtype *beta, sunrealtype *wrk);
SUNDIALS_EXPORT int DenseORMQR(SUNMatrix A, sunrealtype *beta, sunrealtype *vn, sunrealtype *vm,
			       sunrealtype *wrk);

SUNDIALS_EXPORT int denseGEQRF(sunrealtype **a, long int m, long int n, sunrealtype *beta, sunrealtype *v);
SUNDIALS_EXPORT int denseORMQR(sunrealtype **a, long int m, long int n, sunrealtype *beta,
			       sunrealtype *v, sunrealtype *w, sunrealtype *wrk);

/*
 * -----------------------------------------------------------------
 * Function : DenseCopy
 * -----------------------------------------------------------------
 * DenseCopy copies the contents of the M-by-N matrix A into the
 * M-by-N matrix B.
 * 
 * DenseCopy is a wrapper around denseCopy which accesses the data
 * in the SUNMatrix A and B (i.e. the fields cols)
 * -----------------------------------------------------------------
 */

SUNDIALS_EXPORT void DenseCopy(SUNMatrix A, SUNMatrix B);
SUNDIALS_EXPORT void denseCopy(sunrealtype **a, sunrealtype **b, long int m, long int n);

/*
 * -----------------------------------------------------------------
 * Function: DenseScale
 * -----------------------------------------------------------------
 * DenseScale scales the elements of the M-by-N matrix A by the
 * constant c and stores the result back in A.
 *
 * DenseScale is a wrapper around denseScale which performs the actual
 * scaling by accessing the data in the SUNMatrix A (i.e. the field
 * cols).
 * -----------------------------------------------------------------
 */

SUNDIALS_EXPORT void DenseScale(sunrealtype c, SUNMatrix A);
SUNDIALS_EXPORT void denseScale(sunrealtype c, sunrealtype **a, long int m, long int n);


/*
 * -----------------------------------------------------------------
 * Function: denseAddIdentity
 * -----------------------------------------------------------------
 * denseAddIdentity adds the identity matrix to the n-by-n matrix
 * stored in the sunrealtype** arrays.
 * -----------------------------------------------------------------
 */

SUNDIALS_EXPORT void denseAddIdentity(sunrealtype **a, long int n);

#ifdef __cplusplus
}
#endif

#endif
