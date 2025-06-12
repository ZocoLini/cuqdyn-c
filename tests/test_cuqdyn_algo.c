#include <assert.h>
#include <cuqdyn.h>
#include <math.h>
#include <stdio.h>

#include "config.h"
void test_lotka_volterra();
void test_nfkb();

int main(void)
{
#ifdef MPI2
    printf("No tests to execute with MPI2\n");
    return 0;
#endif

    test_lotka_volterra();
    printf("\tTest 1 completed\n");

    test_nfkb();
    printf("\tTest 2 completed\n");

    return 0;
}

void test_lotka_volterra()
{
    char *data_file = "data/lotka_volterra_paper_data.txt";
    char *cuqdyn_config_file = "data/lotka_volterra_cuqdyn_config.xml";
    char *sacess_config_file = "data/lotka_volterra_ess_config_nl2sol.dn2gb.xml";
    char *output_file = "data/output";

    init_cuqdyn_conf_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);
}

void test_nfkb()
{
    char *data_file = "data/nfkb_paper_data.txt";
    char *cuqdyn_config_file = "data/nfkb_cuqdyn_config.xml";
    char *sacess_config_file = "data/nfkb_ess_mpi_config.xml";
    char *output_file = "data/output";

    init_cuqdyn_conf_from_file(cuqdyn_config_file);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);
}
