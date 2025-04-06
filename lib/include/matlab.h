//
// Created by borja on 03/04/25.
//

#ifndef MATLAB_H
#define MATLAB_H

#include <lib.h>
#include <sunmatrix/sunmatrix_dense.h>

N_Vector copy_vector_remove_indices(N_Vector, Array, SUNContext);
SUNMatrix copy_matrix_remove_rows(SUNMatrix, Array, SUNContext);
SUNMatrix copy_matrix_remove_columns(SUNMatrix, Array, SUNContext);
SUNMatrix copy_matrix_remove_rows_and_columns(SUNMatrix, Array, Array, SUNContext);

#endif //MATLAB_H
