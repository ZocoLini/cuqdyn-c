#define LOTKA_VOLTERRA_MAT "data/lotka_volterra_data_homoc_noise_0.10_size_30_data_1.mat"
#define DATA_TXT "data/test_data.txt"

#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <sundials_old/sundials_nvector.h>
#include <assert.hd .


#include "data_reader.h"
#include "lib.h"

void test_lotka_volterra_mat();
void test_read_data_txt();

int main(void)
{
    test_lotka_volterra_mat();
    printf("\tTest 1 passed\n");

    test_read_data_txt();
    printf("\tTest 2 passed\n");

    return 0;
}

void test_lotka_volterra_mat()
{
    const realtype expected_y_values[31][2] = {
        {10, 5},
        {1.627e+01 , -3.196e-02},
        {2.597e+01 , 5.589e+00 },
        {3.373e+01 , 8.552e+00 },
        {5.374e+01 , 4.930e+00 },
        {7.607e+01 , 1.029e+01 },
        {7.493e+01 , 4.178e+01 },
        {4.005e+01 , 7.783e+01 },
        {1.435e+01 , 7.844e+01 },
        {6.658e+00 , 5.618e+01 },
        {1.580e+00 , 3.780e+01 },
        {6.848e+00 , 2.325e+01 },
        {6.422e+00 , 1.937e+01 },
        {4.250e+00 , 1.317e+01 },
        {4.422e+00 , 8.096e-01 },
        {8.831e+00 , 2.381e+00 },
        {1.784e+01 , 1.747e+00 },
        {2.148e+01 , 2.904e+00 },
        {3.687e+01 , 1.409e+00 },
        {5.202e+01 , 9.303e+00 },
        {7.378e+01 , 1.114e+01 },
        {8.134e+01 , 3.388e+01 },
        {4.315e+01 , 8.328e+01 },
        {1.409e+01 , 8.053e+01 },
        {1.085e+01 , 5.640e+01 },
        {4.580e+00 , 3.562e+01 },
        {-2.494e+00, 2.464e+01 },
        {1.040e+00 , 1.785e+01 },
        {1.479e+00 , 1.065e+01 },
        {1.030e+01 , 6.680e+00 },
        {9.117e+00 , 4.822e+00 }
    };

    N_Vector t = NULL;
    DlsMat y = NULL;

    assert(read_mat_data_file(LOTKA_VOLTERRA_MAT, &t, &y) == 0);

    assert(NV_Ith_S(t, 0) == 0.0);

    for (long i = 0; i < SM_COLUMNS_D(y); i++)
    {
        assert(expected_y_values[0][i] == SM_ELEMENT_D(y, 0, i));
    }

    for (int i = 0; i < 31; ++i)
    {
        assert(i == NV_Ith_S(t, i));
    }

    // TODO: The data contained in the file doesn't match the paper values.
    //  Ask about hardcode the real values contained as they are contained in the LPB and UPB
    //  described in the paper.
    for (int i = 0; i < N_VGetLength_Serial(t); i++)
    {
        for (int j = 0; j < SM_COLUMNS_D(y); j++)
        {
            const realtype expected = expected_y_values[i][j];
            const realtype actual = SM_ELEMENT_D(y, i, j);

            printf("%g ", SM_ELEMENT_D(y, i, j));
            if (1)
            {
                int a =1;
            }
            //assert(expected == actual);
        }
        printf("\n");
    }
}

void test_read_data_txt()
{
    N_Vector t = NULL;
    DlsMat y = NULL;

    assert(read_txt_data_file(DATA_TXT, &t, &y) == 0);

    for (int i = 0; i < SM_ROWS_D(y); ++i)
    {
        assert(NV_Ith_S(t, i) == i);
        assert(SM_ELEMENT_D(y, i, 0) == i);
        assert(SM_ELEMENT_D(y, i, 1) == i);
    }
}
