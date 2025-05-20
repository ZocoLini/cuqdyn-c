#include <assert.h>
#include <stdio.h>

#include "cuqdyn.h"
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

    realtype values1[12] = {2, 7, 8, 9, 2, 8, 7, 2, 4, 5, 5, 6};
    realtype values2[12] = {6, 6, 6, 5, 4, 3, 7, 8, 9, 1, 3, 7};
    realtype values3[12] = {1, 4, 5, 6, 8, 7, 3, 2, 9, 9, 9, 9};
    realtype values4[12] = {1, 4, 5, 6, 8, 7, 3, 2, 9, 9, 9, 9};

    realtype medians[12] = {1.5, 5, 5.5, 6, 6, 7, 5, 2, 9, 7, 7, 8};

    DlsMat matrix1 = SUNDenseMatrix(3, 4);
    DlsMat matrix2 = SUNDenseMatrix(3, 4);
    DlsMat matrix3 = SUNDenseMatrix(3, 4);
    DlsMat matrix4 = SUNDenseMatrix(3, 4);

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

    DlsMat median_matrix = matrix_array_get_median(matrix_array);

    assert(median_matrix != NULL);

    realtype *median_matrix_data = SM_DATA_D(median_matrix);

    for (int i = 0; i < 12; ++i)
    {
        realtype a = median_matrix_data[i];
        realtype b = medians[i];

        assert(a == b);
    }
}

void test_odd_matrices()
{
    MatrixArray matrix_array = create_matrix_array(3);

    realtype values1[12] = {2, 7, 8, 9, 2, 8, 7, 2, 4, 5, 5, 6};
    realtype values2[12] = {6, 6, 6, 5, 4, 3, 7, 8, 9, 1, 3, 7};
    realtype values3[12] = {1, 4, 5, 6, 8, 7, 3, 2, 9, 9, 9, 9};

    realtype medians[12] = {2, 6, 6, 6, 4, 7, 7, 2, 9, 5, 5, 7};

    DlsMat matrix1 = SUNDenseMatrix(3, 4);
    DlsMat matrix2 = SUNDenseMatrix(3, 4);
    DlsMat matrix3 = SUNDenseMatrix(3, 4);

    for (int i = 0; i < 12; ++i)
    {
        SM_DATA_D(matrix1)[i] = values1[i];
        SM_DATA_D(matrix2)[i] = values2[i];
        SM_DATA_D(matrix3)[i] = values3[i];
    }

    matrix_array_set_index(matrix_array, 0, matrix1);
    matrix_array_set_index(matrix_array, 1, matrix2);
    matrix_array_set_index(matrix_array, 2, matrix3);

    DlsMat median_matrix = matrix_array_get_median(matrix_array);

    assert(median_matrix != NULL);

    realtype *median_matrix_data = SM_DATA_D(median_matrix);

    for (int i = 0; i < 12; ++i)
    {
        realtype a = median_matrix_data[i];
        realtype b = medians[i];

        assert(a == b);
    }
}
