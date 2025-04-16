#include <assert.h>
#include <stdio.h>



#include "lib.h"
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
    realtype values1[5] = {5, 4, 2, 1, 8};
    realtype values2[5] = {6, 3, 8, 6, 2};
    realtype values3[5] = {1, 4, 2, 9, 0};
    realtype values4[5] = {3, 2, 6, 5, 8};

    realtype medians[5] = {4, 3.5, 4, 5.5, 5};

    DlsMat matrix = SUNDenseMatrix(4, 5, get_sun_context());

    for (int j = 0; j < 5; ++j)
    {
        SM_DATA_D(matrix)[0 * 5 + j] = values1[j];
        SM_DATA_D(matrix)[1 * 5 + j] = values2[j];
        SM_DATA_D(matrix)[2 * 5 + j] = values3[j];
        SM_DATA_D(matrix)[3 * 5 + j] = values4[j];
    }

    N_Vector medians_vector = get_matrix_cols_median(matrix);

    assert(medians_vector != NULL);

    realtype *medians_vector_data = NV_DATA_S(medians_vector);

    for (int i = 0; i < 5; ++i)
    {
        realtype expected = medians[i];
        realtype obtained = medians_vector_data[i];

        assert(expected == obtained);
    }
}

void test_odd_vec()
{
    realtype values1[5] = {5, 4, 2, 1, 8};
    realtype values2[5] = {6, 3, 8, 6, 2};
    realtype values3[5] = {1, 4, 2, 9, 0};

    realtype medians[5] = {5, 4, 2, 6, 2};

    DlsMat matrix = SUNDenseMatrix(3, 5, get_sun_context());

    for (int j = 0; j < 5; ++j)
    {
        SM_DATA_D(matrix)[0 * 5 + j] = values1[j];
        SM_DATA_D(matrix)[1 * 5 + j] = values2[j];
        SM_DATA_D(matrix)[2 * 5 + j] = values3[j];
    }

    N_Vector medians_vector = get_matrix_cols_median(matrix);

    assert(medians_vector != NULL);

    realtype *medians_vector_data = NV_DATA_S(medians_vector);

    for (int i = 0; i < 5; ++i)
    {
        realtype expected = medians[i];
        realtype obtained = medians_vector_data[i];

        assert(expected == obtained);
    }
}
