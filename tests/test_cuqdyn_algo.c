#include <cuqdyn.h>
#include <stdio.h>
void test_lotka_volterra();

int main(void)
{
    test_lotka_volterra();
    printf("Test 1 completed");
    return 0;
}

void test_lotka_volterra()
{
    char *data_file = "data/lotka_volterra_data_homoc_noise_0.10_size_30_data_1.mat";
    char *sacess_config_file = "data/lotka_volterra_ess_config.xml";
    char *output_file = "output";

    CuqdynResult *cuqdyn_result = cuqdyn_algo(LOTKA_VOLTERRA, data_file, sacess_config_file, output_file);
}