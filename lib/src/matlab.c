#include <nvector/nvector_serial.h>
#include <sundials/sundials_types.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "lib.h"

// num_indices are the indices to be removed from the original vector. Should be sorted in ascending order.
// the indices are 1-based, so the first element is 1, not 0.
N_Vector copy_vector_remove_indices(N_Vector original, LongArray indices)
{
    sunrealtype *original_data = N_VGetArrayPointer(original);
    sunindextype N = N_VGetLength(original);

    N_Vector new_vector = N_VNew_Serial(N - indices.len, get_sun_context());

    sunrealtype *new_data = N_VGetArrayPointer(new_vector);

    long new_index = 0; // Index to track the current index in the new vector
    long skip_index = 0; // Index to track the current index in the indices array

    for (long i = 0; i < N; i++)
    {
        if (skip_index < indices.len && i == array_get_index(indices, skip_index) - 1)
        {
            skip_index++;
            continue;
        }

        new_data[new_index++] = original_data[i];
    }

    return new_vector;
}

// the indices are 1-based
SUNMatrix copy_matrix_remove_rows_and_columns(SUNMatrix matrix, LongArray row_indices, LongArray col_indices)
{
    const sunindextype rows = SM_ROWS_D(matrix);
    const sunindextype cols = SM_COLUMNS_D(matrix);

    SUNMatrix copy = SUNDenseMatrix(rows - row_indices.len, cols - col_indices.len, get_sun_context());

    sunrealtype *original_data = SM_DATA_D(matrix);
    sunrealtype *copy_data = SM_DATA_D(copy);

    // copy_index: Index to track the current index in the copy matrix
    // row_skip_index: Index to track the current index in the row_indices array
    // col_skip_index: Index to track the current index in the col_indices array

    for (long i = 0, copy_index = 0, row_skip_index = 0, col_skip_index = 0; i < rows * cols; i++)
    {
        long row = i / cols; // Row index in the original matrix
        long col = i % cols; // Column index in the original matrix

        if (row_skip_index < row_indices.len && row == array_get_index(row_indices, row_skip_index) - 1)
        {
            i += cols - 1; // Skip the entire row (-1 because the for loop will increment i by 1 after the continue)
            row_skip_index++;
            continue;
        }

        if (col_skip_index < col_indices.len && col == array_get_index(col_indices, col_skip_index) - 1)
        {
            col_skip_index++;

            // We reset the iteration over col_indices once we reach the end. we
            // probably need to iterate over a new row in the original matrix if there is some left
            if (col_skip_index == col_indices.len)
            {
                col_skip_index = 0;
            }

            continue;
        }

        copy_data[copy_index++] = original_data[i];
    }


    return copy;
}

// the indices are 1-based
SUNMatrix copy_matrix_remove_rows(SUNMatrix matrix, LongArray indices)
{
    return copy_matrix_remove_rows_and_columns(matrix, indices, create_empty_array());
}

// the indices are 1-based
SUNMatrix copy_matrix_remove_columns(SUNMatrix matrix, LongArray indices)
{
    return copy_matrix_remove_rows_and_columns(matrix, create_empty_array(), indices);
}

void set_matrix_row(SUNMatrix matrix, N_Vector vec, const sunindextype row_index, const sunindextype start,
                    const sunindextype end)
{
    for (long i = start; i < end; ++i)
    {
        SM_ELEMENT_D(matrix, row_index, i) = NV_Ith_S(vec, i);
    }
}

void set_matrix_column(SUNMatrix matrix, N_Vector vec, const sunindextype col_index, const sunindextype start,
                       const sunindextype end)
{
    for (long i = start; i < end; ++i)
    {
        SM_ELEMENT_D(matrix, i, col_index) = NV_Ith_S(vec, i);
    }
}

N_Vector copy_matrix_row(SUNMatrix matrix, sunindextype row_index, sunindextype start, sunindextype end)
{
    N_Vector vec = N_VNew_Serial(end - start, get_sun_context());

    for (long i = start; i < end; ++i)
    {
        NV_Ith_S(vec, i - start) = SM_ELEMENT_D(matrix, row_index, i);
    }

    return vec;
}

N_Vector copy_matrix_column(SUNMatrix matrix, sunindextype col_index, sunindextype start, sunindextype end)
{
    N_Vector vec = N_VNew_Serial(end - start, get_sun_context());

    for (long i = start; i < end; ++i)
    {
        NV_Ith_S(vec, i - start) = SM_ELEMENT_D(matrix, i, col_index);
    }

    return vec;
}

sunrealtype quantile(N_Vector, sunrealtype)
{

}
