//
// Created by borja on 4/4/25.
//

#include <stdio.h>
#include <matlab.h>
#include <nvector/nvector_serial.h>
#include <sundials/sundials_nvector.h>

void test_copy_vector_remove_indices(SUNContext);
void test_copy_matrix_remove_rows(SUNContext);

int main(void)
{
    SUNContext sunctx;
    SUNContext_Create(SUN_COMM_NULL, &sunctx);

    test_copy_vector_remove_indices(sunctx);
    printf("\tTest 1 passed\n");

    test_copy_matrix_remove_rows(sunctx);
    printf("\tTest 2 passed\n");
    return 0;
}

void test_copy_vector_remove_indices(SUNContext sunctx)
{
    N_Vector vector = N_VNew_Serial(5, sunctx);

    sunrealtype *data = N_VGetArrayPointer(vector);
    for (int i = 0; i < 5; ++i)
    {
        data[i] = i + 1;
    }

    N_Vector copy = copy_vector_remove_indices(vector, (int[]){1, 3}, sunctx);

    data = N_VGetArrayPointer(copy);

    assert(NV_LENGTH_S(copy) == 3);
    assert(data[0] == 2);
    assert(data[1] == 4);
    assert(data[2] == 5);

    // Clean up
    N_VDestroy(vector);
    N_VDestroy(copy);
}

void test_copy_matrix_remove_rows(SUNContext sunctx)
{
    SUNMatrix matrix = SUNDenseMatrix(3, 3, sunctx);

    sunrealtype *data = SM_DATA_D(matrix);
    for (int i = 0; i < 9; ++i)
    {
        data[i] = i + 1;
    }

    SUNMatrix copy = copy_matrix_remove_rows(matrix, (int[]){1, 2}, sunctx);

    assert(SM_ROWS_D(copy) == 1);
    assert(SM_COLUMNS_D(copy) == 3);

    data = SM_DATA_D(copy);

    assert(data[0] == 7);
    assert(data[1] == 8);
    assert(data[2] == 9);

    SUNMatDestroy(copy);
    SUNMatDestroy(matrix);
}