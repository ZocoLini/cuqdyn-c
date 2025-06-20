#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "cuqdyn.h"

N_Vector copy_vector_remove_indices(N_Vector original, LongArray indices)
{
    sunrealtype *original_data = N_VGetArrayPointer(original);
    long N = NV_LENGTH_S(original);

    N_Vector new_vector = New_Serial(N - indices.len);

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
    const long rows = SM_ROWS_D(matrix);
    const long cols = SM_COLUMNS_D(matrix);

    SUNMatrix copy = NewDenseMatrix(rows - row_indices.len, cols - col_indices.len);

    sunrealtype *original_data = SM_DATA_D(matrix);
    sunrealtype *copy_data = SM_DATA_D(copy);

    // copy_index: Index to track the current index in the copy matrix
    // row_skip_index: Index to track the current index in the row_indices array
    // col_skip_index: Index to track the current index in the col_indices array

    long copy_index = 0;

    long row_skip_index = 0;
    long col_skip_index = 0;

    for (long i = 0; i < rows * cols; i++)
    {
        const long row = i % rows; // Row index in the original matrix
        const long col = i / rows; // Column index in the original matrix

        if (row_skip_index < row_indices.len && row == array_get_index(row_indices, row_skip_index) - 1)
        {
            row_skip_index++;

            // We reset the iteration over row_indices once we reach the end. we
            // probably need to iterate over a new col in the original matrix if there is some left
            if (row_skip_index == row_indices.len)
            {
                row_skip_index = 0;
            }

            continue;
        }

        if (col_skip_index < col_indices.len && col == array_get_index(col_indices, col_skip_index) - 1)
        {
            i += rows - 1; // Skip the entire col (-1 because the for loop will increment i by 1 after the continue)
            col_skip_index++;
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

void set_matrix_row(SUNMatrix matrix, N_Vector vec, const long row_index, const long start,
                    const long end)
{
    for (long i = start; i < end; ++i)
    {
        SM_ELEMENT_D(matrix, row_index, i) = NV_Ith_S(vec, i - start);
    }
}

void set_matrix_column(SUNMatrix matrix, N_Vector vec, const long col_index, const long start,
                       const long end)
{
    for (long i = start; i < end; ++i)
    {
        SM_ELEMENT_D(matrix, i, col_index) = NV_Ith_S(vec, i - start);
    }
}

N_Vector copy_matrix_row(SUNMatrix matrix, long row_index, long start, long end)
{
    N_Vector vec = New_Serial(end - start);

    for (long i = start; i < end; ++i)
    {
        NV_Ith_S(vec, i - start) = SM_ELEMENT_D(matrix, row_index, i);
    }

    return vec;
}

N_Vector copy_matrix_column(SUNMatrix matrix, long col_index, long start, long end)
{
    N_Vector vec = New_Serial(end - start);

    for (long i = start; i < end; ++i)
    {
        NV_Ith_S(vec, i - start) = SM_ELEMENT_D(matrix, i, col_index);
    }

    return vec;
}

SUNMatrix sum_two_matrices(SUNMatrix a, SUNMatrix b)
{
    long rows = SM_ROWS_D(b);
    long cols = SM_COLUMNS_D(b);

    if (SM_ROWS_D(a) < rows || SM_COLUMNS_D(a) < cols)
    {
        return NULL;
    }

    SUNMatrix result = NewDenseMatrix(SM_ROWS_D(a), SM_COLUMNS_D(a));

    for (long i = 0; i < rows * cols; i++)
    {
        SM_DATA_D(result)[i] = SM_DATA_D(a)[i] + SM_DATA_D(b)[i];
    }

    return result;
}

SUNMatrix subtract_two_matrices(SUNMatrix a, SUNMatrix b)
{
    long rows = SM_ROWS_D(b);
    long cols = SM_COLUMNS_D(b);

    if (SM_ROWS_D(a) < rows || SM_COLUMNS_D(a) < cols)
    {
        return NULL;
    }

    SUNMatrix result = NewDenseMatrix(SM_ROWS_D(a), SM_COLUMNS_D(a));

    for (long i = 0; i < rows * cols; i++)
    {
        SM_DATA_D(result)[i] = SM_DATA_D(a)[i] - SM_DATA_D(b)[i];
    }

    return result;
}

int cmp_sunrealtype(const void *a, const void *b)
{
    double x = *(sunrealtype *) a;
    double y = *(sunrealtype *) b;

    if (x < y)
        return -1;
    if (x > y)
        return 1;
    return 0;
}

sunrealtype quantile(N_Vector vec, sunrealtype q)
{
    const long n = NV_LENGTH_S(vec);
    sunrealtype *data = malloc(n * sizeof(sunrealtype));

    memcpy(data, NV_DATA_S(vec), n * sizeof(sunrealtype));

    qsort(data, n, sizeof(sunrealtype), cmp_sunrealtype);

    const double min_q = 0.5 / (sunrealtype) n;
    const double max_q = ((sunrealtype) n - 0.5) / (sunrealtype) n;

    if (q <= min_q) {
        const double val = data[0];
        free(data);
        return val;
    }
    if (q >= max_q)
    {
        const double val = data[n - 1];
        free(data);
        return val;
    }

    const double pos = q * (sunrealtype) n - 0.5;
    const int i = (int) pos;
    const double delta = pos - i;

    const double result = data[i] * (1 - delta) + data[i + 1] * delta;
    free(data);
    return result;
}
