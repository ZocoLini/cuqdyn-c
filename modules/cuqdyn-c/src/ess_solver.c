#include <stdlib.h>

#include <method_module/structure_paralleltestbed.h>

#ifdef MPI2
        #include <mpi.h>
#endif

#ifdef OPENMP
        #include <omp.h>
#endif

// TODO: Use texp and yexp inside the objective function somehow
double* execute_ess_solver(const char *file, const char *path, void *(*obj_func)(double *, void *), N_Vector texp, DlsMat yexp)
{
    int id, NPROC, error, i, NPROC_OPENMP;
    experiment_total *exptotal;
    result_solver result;
    int first, init;

#ifdef MPI2
    // Original call MPI_Init(&argc, &argv);
    int err = MPI_Comm_size(MPI_COMM_WORLD, &NPROC);

    if (err != MPI_SUCCESS) {
        fprintf(stderr, "MPI_COMM_WORLD failed\n");
        exit(1);
    }

    MPI_Comm_rank(MPI_COMM_WORLD, &id);
#else
    id = 0;
    NPROC = 1;
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
        create_expetiment_struct(file, &(exptotal[i]), NPROC, id, path, init);
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
    create_expetiment_struct(file, &exptotal[0], NPROC, id, path, init);

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
    execute_Solver(exptotal, &result, obj_func);

    return result.bestx_value;

    destroyexp(exptotal);

#ifdef MPI2
    MPI_Finalize();
#endif
}
