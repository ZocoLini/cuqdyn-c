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

sunrealtype quantile(N_Vector, sunrealtype);
#endif //MATLAB_H
