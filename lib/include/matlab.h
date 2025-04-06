//
// Created by borja on 03/04/25.
//

#ifndef MATLAB_H
#define MATLAB_H

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

N_Vector copy_vector_remove_indices(N_Vector, int *, SUNContext);
SUNMatrix copy_matrix_remove_rows(SUNMatrix, int *, SUNContext);
SUNMatrix copy_matrix_remove_columns(SUNMatrix, int *, SUNContext);
SUNMatrix copy_matrix_remove_rows_and_columns(SUNMatrix, int *, int *, SUNContext);

#endif //MATLAB_H
