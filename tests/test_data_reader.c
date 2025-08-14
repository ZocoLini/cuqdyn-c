#define LOTKA_VOLTERRA_MAT "data/lotka_volterra_data_homoc_noise_0.10_size_30_data_1.mat"
#define DATA_TXT "data/test_data.txt"

#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <assert.h>


#include "data_reader.h"
#include "cuqdyn.h"

void test_read_data_txt();

int main(void)
{
    test_read_data_txt();
    printf("\tTest 1 passed\n");

    return 0;
}

void test_read_data_txt()
{
    N_Vector t = NULL;
    SUNMatrix y = NULL;

    assert(read_txt_data_file(DATA_TXT, &t, &y) == 0);

    for (int i = 0; i < SM_ROWS_D(y); ++i)
    {
        assert(NV_Ith_S(t, i) == i);
        assert(SM_ELEMENT_D(y, i, 0) == i);
        assert(SM_ELEMENT_D(y, i, 1) == i);
    }
}
