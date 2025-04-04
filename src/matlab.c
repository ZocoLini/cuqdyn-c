//
// Created by borja on 03/04/25.
//

#include <nvector/nvector_serial.h>
#include <sundials/sundials_types.h>
#include <sunmatrix/sunmatrix_dense.h>

// num_indices are the indices to be removed from the original vector. Should be sorted in ascending order.
// the indices are 1-based, so the first element is 1, not 0.
N_Vector copy_vector_remove_indices(N_Vector original, const int *indices, SUNContext sunctx)
{
    sunrealtype *original_data = N_VGetArrayPointer(original);
    sunindextype N = N_VGetLength(original);
    long indices_len = sizeof(indices) / sizeof(indices[0]);

    N_Vector new_vector = N_VNew_Serial(N - indices_len, sunctx);


    sunrealtype *new_data = N_VGetArrayPointer(new_vector);

    long new_index = 0; // Index to track the current index in the new vector
    long skip_index = 0; // Index to track the current index in the indices array

    for (long i = 0; i < N; i++) {
        if (skip_index < indices_len && i == indices[skip_index] - 1) {
            skip_index++;
            continue;
        }

        new_data[new_index++] = original_data[i];
    }

    return new_vector;
}

// the indices are 1-based
SUNMatrix copy_matrix_remove_rows_and_columns(SUNMatrix, const int *row_indices, const int *col_indices, SUNContext sunctx)
{

}

// the indices are 1-based
SUNMatrix copy_matrix_remove_rows(SUNMatrix matrix, const int *indices, SUNContext sunctx)
{
    const sunindextype rows = SM_ROWS_D(matrix);
    const sunindextype cols = SM_COLUMNS_D(matrix);
    long indices_len = sizeof(indices) / sizeof(indices[0]);

    SUNMatrix copy = SUNDenseMatrix(rows - indices_len, cols, sunctx);

    sunrealtype *original_data = SM_DATA_D(matrix);
    sunrealtype *copy_data = SM_DATA_D(copy);

    long copy_index = 0; // Index to track the current index in the copy matrix
    long skip_index = 0; // Index to track the current index in the indices array

    for (long i = 0; i < rows * cols; i++)
    {
        if (skip_index < indices_len && (i / cols) == indices[skip_index] - 1)
        {
            i += cols - 1; // Skip the entire row (-1 because the for loop will increment i by 1 after the continue)
            skip_index++;
            continue;
        }

        copy_data[copy_index++] = original_data[i];
    }


    return copy;
}

// the indices are 1-based
SUNMatrix copy_matrix_remove_columns(SUNMatrix matrix, const int *indices, SUNContext sunctx)
{
    return copy_matrix_remove_rows_and_columns(matrix, (int[]){}, indices, sunctx);
}