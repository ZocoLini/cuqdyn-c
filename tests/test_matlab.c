#include <matlab.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <sundials/sundials_nvector.h>
#include <tgmath.h>

#include "../lib/include/lib.h"

void test_copy_vector_remove_indices();
// TODO: this four funs maybe test indexing first by row instead of column
void test_copy_matrix_remove_rows();
void test_copy_matrix_remove_cols();
void test_copy_matrix_remove_rows_and_cols();

void test_set_matrix_row();
void test_set_matrix_column();

void test_copy_matrix_row();
void test_copy_matrix_column();

void test_quantile();

int main(void)
{
    test_copy_vector_remove_indices();
    printf("\tTest 1 passed\n");

    test_copy_matrix_remove_rows();
    printf("\tTest 2 passed\n");

    test_copy_matrix_remove_cols();
    printf("\tTest 3 passed\n");

    test_copy_matrix_remove_rows_and_cols();
    printf("\tTest 4 passed\n");

    test_set_matrix_row();
    printf("\tTest 5 passed\n");

    test_set_matrix_column();
    printf("\tTest 6 passed\n");

    test_copy_matrix_row();
    printf("\tTest 7 passed\n");

    test_copy_matrix_column();
    printf("\tTest 8 passed\n");

    test_quantile();
    printf("\tTest 9 passed\n");

    return 0;
}

void test_copy_vector_remove_indices()
{
    N_Vector vector = N_VNew_Serial(5, get_sun_context());

    sunrealtype *data = N_VGetArrayPointer(vector);
    for (int i = 0; i < 5; ++i)
    {
        data[i] = i + 1;
    }

    N_Vector copy = copy_vector_remove_indices(vector, create_array((long[]) {1, 3}, 2));

    data = N_VGetArrayPointer(copy);

    assert(NV_LENGTH_S(copy) == 3);
    assert(data[0] == 2);
    assert(data[1] == 4);
    assert(data[2] == 5);

    // Clean up
    N_VDestroy(vector);
    N_VDestroy(copy);
}

void test_copy_matrix_remove_rows()
{
    SUNMatrix matrix = SUNDenseMatrix(3, 3, get_sun_context());

    sunrealtype *data = SM_DATA_D(matrix);
    for (int i = 0; i < 9; ++i)
    {
        data[i] = i + 1;
    }

    SUNMatrix copy = copy_matrix_remove_rows(matrix, create_array((long[]) {1, 2}, 2));

    assert(SM_ROWS_D(copy) == 1);
    assert(SM_COLUMNS_D(copy) == 3);

    data = SM_DATA_D(copy);

    assert(data[0] == 7);
    assert(data[1] == 8);
    assert(data[2] == 9);

    SUNMatDestroy(copy);
    SUNMatDestroy(matrix);
}

void test_copy_matrix_remove_cols()
{
    SUNMatrix matrix = SUNDenseMatrix(3, 5, get_sun_context());

    sunrealtype *data = SM_DATA_D(matrix);
    for (int i = 0; i < 15; ++i)
    {
        data[i] = i + 1;
    }

    SUNMatrix copy = copy_matrix_remove_columns(matrix, create_array((long[]) {1, 2}, 2));

    assert(SM_ROWS_D(copy) == 3);
    assert(SM_COLUMNS_D(copy) == 3);

    data = SM_DATA_D(copy);

    assert(data[0] == 3);
    assert(data[1] == 4);
    assert(data[2] == 5);
    assert(data[3] == 8);
    assert(data[4] == 9);
    assert(data[5] == 10);
    assert(data[6] == 13);
    assert(data[7] == 14);
    assert(data[8] == 15);

    SUNMatDestroy(copy);
    SUNMatDestroy(matrix);
}

void test_copy_matrix_remove_rows_and_cols()
{
    SUNMatrix matrix = SUNDenseMatrix(4, 3, get_sun_context());

    sunrealtype *data = SM_DATA_D(matrix);
    for (int i = 0; i < 12; ++i)
    {
        data[i] = i + 1;
    }

    SUNMatrix copy = copy_matrix_remove_rows_and_columns(matrix, create_array((long[]) {1, 2, 3}, 3),
                                                         create_array((long[]) {1, 2}, 2));

    assert(SM_ROWS_D(copy) == 1);
    assert(SM_COLUMNS_D(copy) == 1);

    data = SM_DATA_D(copy);

    assert(data[0] == 12);

    SUNMatDestroy(copy);
    SUNMatDestroy(matrix);
}

void test_set_matrix_row()
{
    SUNMatrix matrix = SUNDenseMatrix(3, 3, get_sun_context());
    for (int i = 0; i < 9; ++i)
    {
        SM_DATA_D(matrix)[i] = i + 1;
    }

    N_Vector vector = N_VNew_Serial(3, get_sun_context());
    for (int i = 0; i < 3; ++i)
    {
        NV_Ith_S(vector, i) = 0;
    }

    sunrealtype expected_data[3][3] = {
            1, 4, 7, 0, 0, 0, 3, 6, 9,
    };

    set_matrix_row(matrix, vector, 1, 0, 3);

    for (int i = 0; i < 3; ++i)
    {
        for (int j = 0; j < 3; ++j)
        {
            assert(SM_ELEMENT_D(matrix, i, j) == expected_data[i][j]);
        }
    }
}

void test_set_matrix_column()
{
    SUNMatrix matrix = SUNDenseMatrix(3, 3, get_sun_context());
    for (int i = 0; i < 9; ++i)
    {
        SM_DATA_D(matrix)[i] = i + 1;
    }

    N_Vector vector = N_VNew_Serial(3, get_sun_context());
    for (int i = 0; i < 3; ++i)
    {
        NV_Ith_S(vector, i) = i + 1;
    }

    sunrealtype expected_data[3][3] = {
            1, 4, 7, 1, 5, 8, 2, 6, 9,
    };

    set_matrix_column(matrix, vector, 0, 1, 3);

    for (int i = 0; i < 3; ++i)
    {
        for (int j = 0; j < 3; ++j)
        {
            sunrealtype value = SM_ELEMENT_D(matrix, i, j);
            sunrealtype expected = expected_data[i][j];

            assert(value == expected);
        }
    }
}

void test_copy_matrix_row()
{
    SUNMatrix matrix = SUNDenseMatrix(3, 3, get_sun_context());
    for (int i = 0; i < 9; ++i)
    {
        SM_DATA_D(matrix)[i] = i + 1;
    }

    sunrealtype expected_data[3] = {
            3,
            6,
            9,
    };

    N_Vector vector = copy_matrix_row(matrix, 2, 0, 3);

    for (int i = 0; i < 3; ++i)
    {
        assert(NV_Ith_S(vector, i) == expected_data[i]);
    }
}

void test_copy_matrix_column()
{
    SUNMatrix matrix = SUNDenseMatrix(3, 3, get_sun_context());
    for (int i = 0; i < 9; ++i)
    {
        SM_DATA_D(matrix)[i] = i + 1;
    }

    sunrealtype expected_data[1] = {
            3,
    };

    N_Vector vector = copy_matrix_column(matrix, 0, 2, 3);

    for (int i = 0; i < 1; ++i)
    {
        assert(NV_Ith_S(vector, i) == expected_data[i]);
    }
}

void test_quantile()
{
    N_Vector values = N_VNew_Serial(7, get_sun_context());
    NV_Ith_S(values, 0) = 0.5377;
    NV_Ith_S(values, 1) = 1.8339;
    NV_Ith_S(values, 2) = -2.2588;
    NV_Ith_S(values, 3) = 0.8622;
    NV_Ith_S(values, 4) = 0.3188;
    NV_Ith_S(values, 5) = -1.3077;
    NV_Ith_S(values, 6) = -0.4336;

    sunrealtype q[7] = {1, 0.3, 0.025, 0.25, 0.5, 0.75, 0.975};
    sunrealtype expected[7] = {1.8339, -0.7832, -2.2588, -1.0892, 0.3188, 0.7810, 1.8339};

    for (int i = 0; i < 7; ++i)
    {
        sunrealtype result = quantile(values, q[i]);
        assert(fabs(result - expected[i]) < 0.0001);
    }
}
