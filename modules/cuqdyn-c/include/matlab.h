#ifndef MATLAB_H
#define MATLAB_H

#include <cuqdyn.h>

// Return a copy of a vector removing the indices passed as argument.
// The indices should be sorted in ascending order and 1-based.
N_Vector copy_vector_remove_indices(N_Vector original, LongArray indices);
// Return a copy of a matrix removing the indicated rows.
// The indices should be sorted in ascending order and 1-based.
SUNMatrix copy_matrix_remove_rows(SUNMatrix matrix, LongArray indices);
// Return a copy of a matrix removing the indicated cols.
// // The indices should be sorted in ascending order and 1-based.
SUNMatrix copy_matrix_remove_columns(SUNMatrix matrix, LongArray indices);
// Return a copy of a matrix removing the indicated rows and cols.
// // The indices should be sorted in ascending order and 1-based.
SUNMatrix copy_matrix_remove_rows_and_columns(SUNMatrix matrix, LongArray row_indices, LongArray col_indices);

// Set a row of a matrix with the values of a vector from start (inclusive) to end (exclusive)
void set_matrix_row(SUNMatrix matrix, N_Vector vec, long row_index, long start, long end);
// Set a column of a matrix with the values of a vector from start (inclusive) to end (exclusive)
void set_matrix_column(SUNMatrix matrix, N_Vector vec, long col_index, long start, long end);

// Copy a row of a matrix into a vector from start (inclusive) to end (exclusive)
N_Vector copy_matrix_row(SUNMatrix matrix, long row_index, long start, long end);
// Copy a column of a matrix into a vector from start (inclusive) to end (exclusive)
N_Vector copy_matrix_column(SUNMatrix matrix, long col_index, long start, long end);

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
