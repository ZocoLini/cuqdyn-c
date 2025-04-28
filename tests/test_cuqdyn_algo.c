#include <assert.h>
#include <cuqdyn.h>
#include <math.h>
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

    realtype expected_params[4] = { 0.5, 0.02, 0.5, 0.02 };

    realtype *abs_tol = (realtype[]){1e-6, 1e-6, 1e-6, 1e-6};
    N_Vector abs_vec = N_VNew_Serial(4, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_vec);
    const Tolerances tolerances = create_tolerances(1e-7, abs_vec);
    const TimeConstraints time_constraints = create_time_constraints(1.0, 30.1, 1.0);
    init_cuqdyn_conf(tolerances, time_constraints);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(LOTKA_VOLTERRA, data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    printf("Predicted params median:\n");
    N_Vector predicted_params = cuqdyn_result->predicted_params_median;
    assert(NV_LENGTH_S(predicted_params) == 4);
    for (int i = 0; i < NV_LENGTH_S(predicted_params); ++i)
    {
        printf("\t%f", NV_Ith_S(predicted_params, i));
        for (int i = 0; i < 4; ++i)
        {
            assert(fabs(NV_Ith_S(predicted_params, i) - expected_params[i]) < 0.1);
        }
    }
    printf("\n");
    printf("Predicted data median:\n");
    DlsMat predicted_data = cuqdyn_result->predicted_data_median;
    assert(SM_ROWS_D(predicted_data) == 30);
    assert(SM_COLUMNS_D(predicted_data) == 2);
    for (int i = 0; i < SM_ROWS_D(predicted_data); ++i)
    {
        for (int j = 0; j < SM_COLUMNS_D(predicted_data); ++j)
        {
            printf("\t%f", SM_ELEMENT_D(predicted_data, i, j));
        }
        printf("\n");
    }
}