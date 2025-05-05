#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cuqdyn.h"

N_Vector copy_vector_remove_indices(N_Vector original, LongArray indices)
{
    realtype *original_data = N_VGetArrayPointer(original);
    long N = N_VGetLength_Serial(original);

    N_Vector new_vector = N_VNew_Serial(N - indices.len, get_sun_context());

    realtype *new_data = N_VGetArrayPointer(new_vector);

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
DlsMat copy_matrix_remove_rows_and_columns(DlsMat matrix, LongArray row_indices, LongArray col_indices)
{
    const long rows = SM_ROWS_D(matrix);
    const long cols = SM_COLUMNS_D(matrix);

    DlsMat copy = SUNDenseMatrix(rows - row_indices.len, cols - col_indices.len, get_sun_context());

    realtype *original_data = SM_DATA_D(matrix);
    realtype *copy_data = SM_DATA_D(copy);

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
DlsMat copy_matrix_remove_rows(DlsMat matrix, LongArray indices)
{
    return copy_matrix_remove_rows_and_columns(matrix, indices, create_empty_array());
}

// the indices are 1-based
DlsMat copy_matrix_remove_columns(DlsMat matrix, LongArray indices)
{
    return copy_matrix_remove_rows_and_columns(matrix, create_empty_array(), indices);
}

void set_matrix_row(DlsMat matrix, N_Vector vec, const long row_index, const long start,
                    const long end)
{
    for (long i = start; i < end; ++i)
    {
        SM_ELEMENT_D(matrix, row_index, i) = NV_Ith_S(vec, i - start);
    }
}

void set_matrix_column(DlsMat matrix, N_Vector vec, const long col_index, const long start,
                       const long end)
{
    for (long i = start; i < end; ++i)
    {
        SM_ELEMENT_D(matrix, i, col_index) = NV_Ith_S(vec, i - start);
    }
}

N_Vector copy_matrix_row(DlsMat matrix, long row_index, long start, long end)
{
    N_Vector vec = N_VNew_Serial(end - start, get_sun_context());

    for (long i = start; i < end; ++i)
    {
        NV_Ith_S(vec, i - start) = SM_ELEMENT_D(matrix, row_index, i);
    }

    return vec;
}

N_Vector copy_matrix_column(DlsMat matrix, long col_index, long start, long end)
{
    N_Vector vec = N_VNew_Serial(end - start, get_sun_context());

    for (long i = start; i < end; ++i)
    {
        NV_Ith_S(vec, i - start) = SM_ELEMENT_D(matrix, i, col_index);
    }

    return vec;
}

DlsMat sum_two_matrices(DlsMat a, DlsMat b)
{
    long rows = SM_ROWS_D(b);
    long cols = SM_COLUMNS_D(b);

    if (SM_ROWS_D(a) < rows || SM_COLUMNS_D(a) < cols)
    {
        return NULL;
    }

    DlsMat result = SUNDenseMatrix(SM_ROWS_D(a), SM_COLUMNS_D(a), get_sun_context());

    for (long i = 0; i < rows * cols; i++)
    {
        SM_DATA_D(result)[i] = SM_DATA_D(a)[i] + SM_DATA_D(b)[i];
    }

    return result;
}

DlsMat subtract_two_matrices(DlsMat a, DlsMat b)
{
    long rows = SM_ROWS_D(b);
    long cols = SM_COLUMNS_D(b);

    if (SM_ROWS_D(a) < rows || SM_COLUMNS_D(a) < cols)
    {
        return NULL;
    }

    DlsMat result = SUNDenseMatrix(SM_ROWS_D(a), SM_COLUMNS_D(a), get_sun_context());

    for (long i = 0; i < rows * cols; i++)
    {
        SM_DATA_D(result)[i] = SM_DATA_D(a)[i] - SM_DATA_D(b)[i];
    }

    return result;
}

int cmp_realtype(const void *a, const void *b)
{
    double x = *(realtype *) a;
    double y = *(realtype *) b;

    if (x < y)
        return -1;
    if (x > y)
        return 1;
    return 0;
}

realtype quantile(N_Vector vec, realtype q)
{
    const long n = NV_LENGTH_S(vec);
    realtype *data = malloc(n * sizeof(realtype));

    memcpy(data, NV_DATA_S(vec), n * sizeof(realtype));

    qsort(data, n, sizeof(realtype), cmp_realtype);

    const double min_q = 0.5 / (realtype) n;
    const double max_q = ((realtype) n - 0.5) / (realtype) n;

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

    const double pos = q * (realtype) n - 0.5;
    const int i = (int) pos;
    const double delta = pos - i;

    const double result = data[i] * (1 - delta) + data[i + 1] * delta;
    free(data);
    return result;
}
