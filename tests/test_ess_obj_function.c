#include "config.h"
#include "data_reader.h"
#include "example_files.h"
#include "functions.h"
#include "matlab.h"
#include "method_module/structure_paralleltestbed.h"
#include "sunmatrix/sunmatrix_dense.h"

#define MODEL "alpha-pinene"

int main()
{
    CuqDynContext context = init_cuqdyn_context_from_file(example_conf(MODEL));

    CuqdynData data;
    assert(read_data_file(example_data(MODEL), &data) == 0);

    N_Vector texp = data.times;
    SUNMatrix yexp = data.observed_data;
    N_Vector initial_values = copy_matrix_row(yexp, 0, 0, SM_ROWS_D(yexp));

    experiment_total *exp_total = malloc(sizeof(experiment_total));
    create_expetiment_struct(example_sacess_conf(MODEL), &exp_total[0], 1, 0, "output", 1, texp, yexp, initial_values);
    exp_total[0].observed_idx = data.observed_idx;

    double x[5] = {1.0, 1.0, 1.0, 1.0, 1.0};

    output_function *out = obj_func(x, exp_total);

    printf("Value %lf", out->value);

    destroyexp(exp_total);
    destroy_cuqdyn_context(context);

    return 0;
}
