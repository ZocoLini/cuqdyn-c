#include <stdlib.h>

#include <method_module/structure_paralleltestbed.h>

void execute_ess_solver(const char *file, const char *path, void *(*func)(double *, void *))
{
    int NPROC;
    int id;
    result_solver result;

#ifdef MPI2
    // Original call MPI_Init(&argc, &argv);
    MPI_Init(NULL, NULL);
    MPI_Comm_size(MPI_COMM_WORLD, &NPROC);
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
    // INIT MESSAGE
    if ((id == 0))
        init_message(NPROC, &(exptotal[0]), NPROC_OPENMP);
    // INIT BENCHMARK
    first = 1;
    for (i = 0; i < NPROC_OPENMP; i++)
    {
        func = setup_benchmark(&(exptotal[i]), id, &first);
    }

    init_result_data(&result, exptotal[0].test.bench.dim);

#else
    experiment_total *exptotal = (experiment_total *) malloc(sizeof(experiment_total));
    int init = 1;
    create_expetiment_struct(file, exptotal, NPROC, id, path, init);
    // INIT MESSAGE
    int NPROC_OPENMP = 1;
    // INIT BENCHMARK
    int first = 1;

    // INIT RESULT STRUCT
    init_result_data(&result, exptotal->test.bench.dim);

#endif

#ifdef MPI2
    MPI_Barrier(MPI_COMM_WORLD);
#endif
    execute_Solver(exptotal, &result, func);

    destroyexp(exptotal);

#ifdef MPI2
    MPI_Finalize();
#endif
}
