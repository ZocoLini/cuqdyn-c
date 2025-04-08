#include <stdio.h>

#include "lib.h"
void test_even_matrices();
void test_odd_matrices();

int main(void)
{
    test_even_matrices();
    printf("\tTest 1 passed\n");

    test_odd_matrices();
    printf("\tTest 2 passed");

    return 0;
}

void test_even_matrices()
{
    MatrixArray matrix_array = create_matrix_array(4);

    sunrealtype values1[12] = {2, 7, 8, 9, 2, 8, 7, 2, 4, 5, 5, 6};
    sunrealtype values2[12] = {6, 6, 6, 5, 4, 3, 7, 8, 9, 1, 3, 7};
    sunrealtype values3[12] = {1, 4, 5, 6, 8, 7, 3, 2, 9, 9, 9, 9};
    sunrealtype values4[12] = {1, 4, 5, 6, 8, 7, 3, 2, 9, 9, 9, 9};

    sunrealtype medians[12] = {1.5, 5, 5.5, 6, 6, 7, 5, 2, 9, 7, 7, 8};

    SUNMatrix matrix1 = SUNDenseMatrix(3, 4, get_sun_context());
    SUNMatrix matrix2 = SUNDenseMatrix(3, 4, get_sun_context());
    SUNMatrix matrix3 = SUNDenseMatrix(3, 4, get_sun_context());
    SUNMatrix matrix4 = SUNDenseMatrix(3, 4, get_sun_context());

    for (int i = 0; i < 12; ++i)
    {
        SM_DATA_D(matrix1)[i] = values1[i];
        SM_DATA_D(matrix2)[i] = values2[i];
        SM_DATA_D(matrix3)[i] = values3[i];
        SM_DATA_D(matrix4)[i] = values4[i];
    }

    matrix_array_set_index(matrix_array, 0, matrix1);
    matrix_array_set_index(matrix_array, 1, matrix2);
    matrix_array_set_index(matrix_array, 2, matrix3);
    matrix_array_set_index(matrix_array, 3, matrix4);

    SUNMatrix median_matrix = matrix_array_get_median(matrix_array);

    assert(median_matrix != NULL);

    sunrealtype *median_matrix_data = SM_DATA_D(median_matrix);

    for (int i = 0; i < 12; ++i)
    {
        sunrealtype a = median_matrix_data[i];
        sunrealtype b = medians[i];

        assert(a == b);
    }
}

void test_odd_matrices()
{
    MatrixArray matrix_array = create_matrix_array(3);

    sunrealtype values1[12] = {2, 7, 8, 9, 2, 8, 7, 2, 4, 5, 5, 6};
    sunrealtype values2[12] = {6, 6, 6, 5, 4, 3, 7, 8, 9, 1, 3, 7};
    sunrealtype values3[12] = {1, 4, 5, 6, 8, 7, 3, 2, 9, 9, 9, 9};

    sunrealtype medians[12] = {2, 6, 6, 6, 4, 7, 7, 2, 9, 5, 5, 7};

    SUNMatrix matrix1 = SUNDenseMatrix(3, 4, get_sun_context());
    SUNMatrix matrix2 = SUNDenseMatrix(3, 4, get_sun_context());
    SUNMatrix matrix3 = SUNDenseMatrix(3, 4, get_sun_context());

    for (int i = 0; i < 12; ++i)
    {
        SM_DATA_D(matrix1)[i] = values1[i];
        SM_DATA_D(matrix2)[i] = values2[i];
        SM_DATA_D(matrix3)[i] = values3[i];
    }

    matrix_array_set_index(matrix_array, 0, matrix1);
    matrix_array_set_index(matrix_array, 1, matrix2);
    matrix_array_set_index(matrix_array, 2, matrix3);

    SUNMatrix median_matrix = matrix_array_get_median(matrix_array);

    assert(median_matrix != NULL);

    sunrealtype *median_matrix_data = SM_DATA_D(median_matrix);

    for (int i = 0; i < 12; ++i)
    {
        sunrealtype a = median_matrix_data[i];
        sunrealtype b = medians[i];

        assert(a == b);
    }
}
