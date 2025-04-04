//
// Created by borja on 03/04/25.
//

#include <nvector/nvector_serial.h>
#include <sundials/sundials_types.h>
#include <sunmatrix/sunmatrix_dense.h>

// num_indices are the indices to be removed from the original vector. Should be sorted in ascending order.
N_Vector copy_vector_remove_indices(N_Vector original, const int *indices, SUNContext sunctx)
{
    sunrealtype *original_data = N_VGetArrayPointer(original);
    sunindextype N = N_VGetLength(original);
    int indices_len = sizeof(indices) / sizeof(indices[0]);

    N_Vector new_vector = N_VNew_Serial(N - indices_len, sunctx);


    sunrealtype *new_data = N_VGetArrayPointer(new_vector);

    int new_index = 0; // Index to track the current index in the new vector
    int skip_index = 0; // Index to track the current index in the indices array

    for (int i = 0; i < N; i++) {
        if (skip_index < indices_len && i == indices[skip_index]) {
            skip_index++;
            continue;
        }

        new_data[new_index++] = original_data[i];
    }

    return new_vector;
}

SUNMatrix copy_matrix_remove_rows(SUNMatrix, const int *indices, SUNContext sunctx)
{

}

SUNMatrix copy_matrix_remove_columns(SUNMatrix, const int *indices, SUNContext sunctx)
{

}