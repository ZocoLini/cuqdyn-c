#define DATA_TXT "data/test_data.txt"

#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <assert.h>


#include "data_reader.h"

void test_read_data_txt();

int main(void)
{
    test_read_data_txt();
    printf("\tTest 1 passed\n");

    return 0;
}

void test_read_data_txt()
{

    CuqdynData data;
    assert(read_data_file(DATA_TXT, &data) == 0);

    N_Vector t = data.times;
    SUNMatrix y = data.all_state_data;

    assert(y != NULL);
    assert(t != NULL);
    
    for (int i = 0; i < SM_ROWS_D(y); ++i)
    {
        assert(NV_Ith_S(t, i) == i);
        assert(SM_ELEMENT_D(y, 0, i) == i);
        assert(SM_ELEMENT_D(y, 1, i) == i);
    }
}
