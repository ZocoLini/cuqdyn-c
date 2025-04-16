#ifndef MATLAB_H
#define MATLAB_H

#include <lib.h>

N_Vector copy_vector_remove_indices(N_Vector, LongArray);
DlsMat copy_matrix_remove_rows(DlsMat, LongArray);
DlsMat copy_matrix_remove_columns(DlsMat, LongArray);
DlsMat copy_matrix_remove_rows_and_columns(DlsMat, LongArray, LongArray);

void set_matrix_row(DlsMat, N_Vector, long row_index, long start, long end);
void set_matrix_column(DlsMat, N_Vector, long col_index, long start, long end);

N_Vector copy_matrix_row(DlsMat, long row_index, long start, long end);
N_Vector copy_matrix_column(DlsMat, long col_index, long start, long end);

/*
 * Sums matrix a + b. Note that 'b' can have fewer cols or rows than 'a' but not otherwise
 * Returns NULL if the dimensions are not compatible
 */
DlsMat sum_two_matrices(DlsMat a, DlsMat b);
/*
 * Substracts b from a. Note that 'b' can have fewer cols or rows than 'a' but not otherwise
 * Returns NULL if the dimensions are not compatible
 */
DlsMat subtract_two_matrices(DlsMat a, DlsMat b);

/*
 * For an n-element vector A, quantile computes quantiles by using a sorting-based algorithm:
 * The sorted elements in A are taken as the (0.5/n), (1.5/n), ..., ([n – 0.5]/n) quantiles. For example:
 * For a data vector of five elements such as {6, 3, 2, 10, 1},
 * the sorted elements {1, 2, 3, 6, 10} respectively correspond
 * to the 0.1, 0.3, 0.5, 0.7, and 0.9 quantiles.
 *
 * For a data vector of six elements such as {6, 3, 2, 10, 8, 1},
 * the sorted elements {1, 2, 3, 6, 8, 10} respectively correspond
 * to the (0.5/6), (1.5/6), (2.5/6), (3.5/6), (4.5/6), and (5.5/6) quantiles.
 *
 * quantile uses Linear Interpolation to compute quantiles for
 * probabilities between (0.5/n) and ([n – 0.5]/n).
 * For the quantiles corresponding to the probabilities outside that range,
 * quantile assigns the minimum or maximum values of the elements in A.
 */
realtype quantile(N_Vector, realtype);
#endif //MATLAB_H
