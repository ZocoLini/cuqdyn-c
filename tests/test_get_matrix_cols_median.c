#include <assert.h>
#include <stdio.h>
#include <sunmatrix/sunmatrix_dense.h>


#include "cuqdyn.h"
void test_even_vec();
void test_odd_vec();

int main(void)
{
    test_even_vec();
    printf("\tTest 1 passed\n");

    test_odd_vec();
    printf("\tTest 2 passed\n");

    return 0;
}

void test_even_vec()
{
    sunrealtype values1[5] = {5, 4, 2, 1, 8};
    sunrealtype values2[5] = {6, 3, 8, 6, 2};
    sunrealtype values3[5] = {1, 4, 2, 9, 0};
    sunrealtype values4[5] = {3, 2, 6, 5, 8};

    sunrealtype medians[5] = {4, 3.5, 4, 5.5, 5};

    SUNMatrix matrix = NewDenseMatrix(4, 5);

    for (int j = 0; j < 5; ++j)
    {
        SM_ELEMENT_D(matrix, 0, j) = values1[j];
        SM_ELEMENT_D(matrix, 1, j) = values2[j];
        SM_ELEMENT_D(matrix, 2, j) = values3[j];
        SM_ELEMENT_D(matrix, 3, j) = values4[j];
    }

    N_Vector medians_vector = get_matrix_cols_median(matrix);

    assert(medians_vector != NULL);

    sunrealtype *medians_vector_data = NV_DATA_S(medians_vector);

    for (int i = 0; i < 5; ++i)
    {
        sunrealtype expected = medians[i];
        sunrealtype obtained = medians_vector_data[i];

        assert(expected == obtained);
    }
}

void test_odd_vec()
{
    sunrealtype values1[5] = {5, 4, 2, 1, 8};
    sunrealtype values2[5] = {6, 3, 8, 6, 2};
    sunrealtype values3[5] = {1, 4, 2, 9, 0};

    sunrealtype medians[5] = {5, 4, 2, 6, 2};

    SUNMatrix matrix = NewDenseMatrix(3, 5);

    for (int j = 0; j < 5; ++j)
    {
        SM_ELEMENT_D(matrix, 0, j) = values1[j];
        SM_ELEMENT_D(matrix, 1, j) = values2[j];
        SM_ELEMENT_D(matrix, 2, j) = values3[j];
    }

    N_Vector medians_vector = get_matrix_cols_median(matrix);

    assert(medians_vector != NULL);

    sunrealtype *medians_vector_data = NV_DATA_S(medians_vector);

    for (int i = 0; i < 5; ++i)
    {
        sunrealtype expected = medians[i];
        sunrealtype obtained = medians_vector_data[i];

        assert(expected == obtained);
    }
}
