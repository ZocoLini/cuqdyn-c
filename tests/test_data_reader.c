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
    N_Vector t = NULL;
    SUNMatrix y = NULL;

    assert(read_txt_data_file(DATA_TXT, &t, &y) == 0);

    assert(y != NULL);
    assert(t != NULL);
    
    for (int i = 0; i < SM_ROWS_D(y); ++i)
    {
        assert(NV_Ith_S(t, i) == i);
        assert(SM_ELEMENT_D(y, 0, i) == i);
        assert(SM_ELEMENT_D(y, 1, i) == i);
    }
}
