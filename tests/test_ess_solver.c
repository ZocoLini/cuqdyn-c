#define LOTKA_VOLTERRA_MAT "data/lotka_volterra_data_homoc_noise_0.10_size_30_data_1.mat"
#define DATA_TXT "data/test_data.txt"

#include <stdio.h>
#include <assert.h>

#include "ess_solver.h"
#include "lib.h"

void test_1();

int main(void)
{
    test_1();
    printf("\tTest 1 passed\n");

    return 0;
}

void test_1()
{
    execute_ess_solver();
}