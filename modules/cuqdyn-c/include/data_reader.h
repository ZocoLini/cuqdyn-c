#ifndef FILE_READER_H
#define FILE_READER_H

#include <sundials/sundials_nvector.h>
#include <sunmatrix/sunmatrix_dense.h>

/* This function wich type of data file is being read (.txt or .mat) and
 * calls the appropriate function to read it.
 */
int read_data_file(const char *data_file, N_Vector *t, SUNMatrix *y);

/*
 * The file should be two ints, m and n, and a matrix mxn
 *      m n
 *      <matrix>
 * All the data contained in the matrix is the observed data and has this form:
 *      t0 y00 y01 y02 ... y0n
 *      t1 y10 y11 y12 ... y1n
 *      .                   .
 *      .                   .
 *      .                   .
 *      tm ym0 ym1 ym2 ... ymn
 *
 * The time vector is the first column of the matrix [t0, t1, t2, ..., tm]
 * The y matrix is the entire matrix skipping the first column
 *      y00 y01 y02 ... y0n
 *      y10 y11 y12 ... y1n
 *      .                .
 *      .                .
 *      .                .
 *      ym0 ym1 ym2 ... ymn
 */
int read_txt_data_file(const char *data_file, N_Vector *t, SUNMatrix *y);
/*
 * The file should be a single matrix mxn
 * All the data contained in the matrix is the observed data and has this form:
 *      t0 y00 y01 y02 ... y0n
 *      t1 y10 y11 y12 ... y1n
 *      .                   .
 *      .                   .
 *      .                   .
 *      tm ym0 ym1 ym2 ... ymn
 *
 * The time vector is the first column of the matrix [t0, t1, t2, ..., tm]
 * The y matrix is the entire matrix skipping the first column
 *      y00 y01 y02 ... y0n
 *      y10 y11 y12 ... y1n
 *      .                .
 *      .                .
 *      .                .
 *      ym0 ym1 ym2 ... ymn
 */
int read_mat_data_file(const char *data_file, N_Vector *t, SUNMatrix *y);

#endif //FILE_READER_H
