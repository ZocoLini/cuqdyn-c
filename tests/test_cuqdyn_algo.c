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

    realtype *abs_tol = (realtype[]){1e-8, 1e-8, 1e-8, 1e-8};
    N_Vector abs_vec = N_VNew_Serial(4, get_sun_context());
    N_VSetArrayPointer(abs_tol, abs_vec);
    const Tolerances tolerances = create_tolerances(1e-8, abs_vec);
    const TimeConstraints time_constraints = create_time_constraints(1.0, 30.0, 1.0);
    init_cuqdyn_conf(tolerances, time_constraints);

    CuqdynResult *cuqdyn_result = cuqdyn_algo(LOTKA_VOLTERRA, data_file, sacess_config_file, output_file);

    assert(cuqdyn_result != NULL);

    printf("Predicted params median:\n");
    N_Vector predicted_params = cuqdyn_result->predicted_params_median;
    printf("Predicted params lñength = %ld\n", NV_LENGTH_S(predicted_params));
    for (int i = 0; i < NV_LENGTH_S(predicted_params); ++i)
    {
        printf("\t%f", NV_Ith_S(predicted_params, i));
    }
    printf("\n");
    printf("Predicted data median:\n");
    DlsMat predicted_data = cuqdyn_result->predicted_data_median;
    printf("Predicted data rows = %ld\n", SM_ROWS_D(predicted_data));
    printf("Predicted data cols = %ld\n", SM_COLUMNS_D(predicted_data));
    for (int i = 0; i < SM_ROWS_D(predicted_data); ++i)
    {
        for (int j = 0; j < SM_COLUMNS_D(predicted_data); ++j)
        {
            printf("\t%f", SM_ELEMENT_D(predicted_data, i, j));
        }
        printf("\n");
    }

    printf("q_low:\n");
    DlsMat q_low = cuqdyn_result->q_low;
    printf("Predicted q_low rows = %ld\n", SM_ROWS_D(q_low));
    printf("Predicted q_low cols = %ld\n", SM_COLUMNS_D(q_low));
    for (int i = 0; i < SM_ROWS_D(q_low); ++i)
    {
        for (int j = 0; j < SM_COLUMNS_D(q_low); ++j)
        {
            printf("\t%f", SM_ELEMENT_D(q_low, i, j));
        }
        printf("\n");
    }

    printf("q_up:\n");
    DlsMat q_up = cuqdyn_result->q_up;
    printf("Predicted q_up rows = %ld\n", SM_ROWS_D(q_up));
    printf("Predicted q_up cols = %ld\n", SM_COLUMNS_D(q_up));
    for (int i = 0; i < SM_ROWS_D(q_up); ++i)
    {
        for (int j = 0; j < SM_COLUMNS_D(q_up); ++j)
        {
            printf("\t%f", SM_ELEMENT_D(q_up, i, j));
        }
        printf("\n");
    }
}