#include "config.h"
#include "data_reader.h"
#include "example_files.h"
#include "functions.h"
#include "matlab.h"
#include "method_module/evaluationinterface.h"
#include "method_module/structure_paralleltestbed.h"
#include "sunmatrix/sunmatrix_dense.h"

#ifdef MPI
#include <mpi.h>
#endif

#define MODEL "alpha-pinene"

int main(int argc, char **argv)
{
#ifdef MPI
    // create_expetiment_struct talks over the communicator it is given.
    MPI_Init(&argc, &argv);
#else
    (void) argc;
    (void) argv;
#endif

    CuqDynContext context = init_cuqdyn_context_from_file(example_conf(MODEL));

    CuqdynData data;
    assert(read_data_file(example_data(MODEL), &data) == 0);

    N_Vector texp = data.times;
    SUNMatrix yexp = data.observed_data;
    N_Vector initial_values = copy_matrix_row(yexp, 0, 0, SM_ROWS_D(yexp));

    experiment_total *exp_total = malloc(sizeof(experiment_total));
    create_expetiment_struct(example_sacess_conf(MODEL), &exp_total[0], 1, 0, "output", 1, texp, yexp, initial_values,
                             SACESS_COMM_WORLD);
    exp_total[0].observed_idx = data.observed_idx;

    double x[5] = {1.0, 1.0, 1.0, 1.0, 1.0};

    output_function *out = obj_func(x, exp_total);

    printf("Value %lf", out->value);

    deallocateoutputfunction_(out, exp_total);
    destroyexp(exp_total);
    free(exp_total);
    N_VDestroy(data.initial_values);
    free(data.observed_idx);
    destroy_cuqdyn_context(context);

#ifdef MPI
    MPI_Finalize();
#endif

    return 0;
}
