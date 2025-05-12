#include <functions/functions.h>
#include <stdlib.h>
#include <unistd.h>

#include <method_module/structure_paralleltestbed.h>
#include "method_module/solversinterface.h"

#ifdef MPI2
        #include <mpi.h>
#endif

#ifdef OPENMP
        #include <omp.h>
#endif

// TODO: Maybe MPI should be started at the calling lvl
N_Vector execute_ess_solver(const char *file, const char *path, ObjFunc obj_func, N_Vector texp, DlsMat yexp, N_Vector initial_values)
{
    int id, NPROC, error, i, NPROC_OPENMP;
    experiment_total *exptotal;
    result_solver result;
    int first, init;

#ifdef MPI2
    // Original call MPI_Init(&argc, &argv); this should be called from the executable that implments this lib
    int err = MPI_Comm_size(MPI_COMM_WORLD, &NPROC);

    if (err != MPI_SUCCESS) {
        fprintf(stderr, "MPI_COMM_WORLD failed\n");
        exit(1);
    }

    MPI_Comm_rank(MPI_COMM_WORLD, &id);
#else
    id = 0;  // This is the primary process
    NPROC = 1;  // Only one process
#endif

#ifdef OPENMP
#pragma omp parallel
    {
        NPROC_OPENMP = omp_get_num_threads();
    }

    exptotal = (experiment_total *) malloc(NPROC_OPENMP * sizeof(experiment_total));
    init = 1;
    for (i = 0; i < NPROC_OPENMP; i++)
    {
        // PARSE THE OPTIONS OF THE SOLVER
        create_expetiment_struct(file, &(exptotal[i]), NPROC, id, path, init, texp, yexp, initial_values);
        init = 0;
    }
    // // INIT MESSAGE
    // if ((id == 0))
    //     init_message(NPROC, &(exptotal[0]), NPROC_OPENMP);
    // // INIT BENCHMARK
    // first = 1;
    // for (int i = 0; i < NPROC_OPENMP; i++)
    // {
    //     func = setup_benchmark(&(exptotal[i]), id, &first);
    // }

    init_result_data(&result, exptotal[0].test.bench.dim);

#else
    exptotal = (experiment_total *) malloc(sizeof(experiment_total));
    init = 1;
    create_expetiment_struct(file, &exptotal[0], NPROC, id, path, init, texp, yexp, initial_values);

    // INIT MESSAGE
    NPROC_OPENMP = 1;
    // INIT BENCHMARK
    first = 1;

    // INIT RESULT STRUCT
    init_result_data(&result, exptotal->test.bench.dim);

#endif

#ifdef MPI2
    MPI_Barrier(MPI_COMM_WORLD);
#endif

    // TODO: This brakes when using MPI2
    execute_Solver(exptotal, &result, obj_func);

    destroyexp(exptotal);

    N_Vector predicted_params = N_VNew_Serial(exptotal->test.bench.dim);
    N_VSetArrayPointer(result.bestx_value, predicted_params);
    return predicted_params;
}
