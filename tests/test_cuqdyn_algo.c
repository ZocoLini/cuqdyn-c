#include <assert.h>
#include <cuqdyn.h>
#include <stdio.h>

#include "config.h"
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
    char *output_file = "data/output";

    realtype *abs_tol = (realtype[]){1e-6, 1e-6, 1e-6, 1e-6};
    N_Vector abs_vec = N_VNew_Serial(4, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_vec);
    const Tolerances tolerances = create_tolerances(1e-7, abs_vec);
    const TimeConstraints time_constraints = create_time_constraints(1.0, 30.0, 1.0);
    init_cuqdyn_conf(tolerances, time_constraints);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(LOTKA_VOLTERRA, data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    printf("Predicted params median:\n");
    for (int i = 0; i < 4; ++i)
    {
        printf("\t%f", NV_Ith_S(cuqdyn_result->predicted_params_median, i));
    }
    printf("\n");
    printf("Predicted data median:\n");
    for (int i = 0; i < 30; ++i)
    {
        for (int j = 0; j < 2; ++j)
        {
            printf("\t%f", SM_ELEMENT_D(cuqdyn_result->predicted_data_median, i, j));
        }
        printf("\n");
    }
}