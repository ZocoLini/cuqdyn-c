#ifndef MATLAB_H
#define MATLAB_H

#include <lib.h>

N_Vector copy_vector_remove_indices(N_Vector, LongArray);
SUNMatrix copy_matrix_remove_rows(SUNMatrix, LongArray);
SUNMatrix copy_matrix_remove_columns(SUNMatrix, LongArray);
SUNMatrix copy_matrix_remove_rows_and_columns(SUNMatrix, LongArray, LongArray);

void set_matrix_row(SUNMatrix, N_Vector, sunindextype row_index, sunindextype start, sunindextype end);
void set_matrix_column(SUNMatrix, N_Vector, sunindextype col_index, sunindextype start, sunindextype end);

N_Vector copy_matrix_row(SUNMatrix, sunindextype row_index, sunindextype start, sunindextype end);
N_Vector copy_matrix_column(SUNMatrix, sunindextype col_index, sunindextype start, sunindextype end);

/*
 * Sums matrix a + b. Note that 'b' can have fewer cols or rows than 'a' but not otherwise
 * Returns NULL if the dimensions are not compatible
 */
SUNMatrix sum_two_matrices(SUNMatrix a, SUNMatrix b);
/*
 * Substracts b from a. Note that 'b' can have fewer cols or rows than 'a' but not otherwise
 * Returns NULL if the dimensions are not compatible
 */
SUNMatrix subtract_two_matrices(SUNMatrix a, SUNMatrix b);

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
sunrealtype quantile(N_Vector, sunrealtype);
#endif //MATLAB_H
