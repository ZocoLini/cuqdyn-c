#ifndef MATLAB_H
#define MATLAB_H

#include <lib.h>

N_Vector copy_vector_remove_indices(N_Vector, LongArray, SUNContext);
SUNMatrix copy_matrix_remove_rows(SUNMatrix, LongArray, SUNContext);
SUNMatrix copy_matrix_remove_columns(SUNMatrix, LongArray, SUNContext);
SUNMatrix copy_matrix_remove_rows_and_columns(SUNMatrix, LongArray, LongArray, SUNContext);

#endif //MATLAB_H
