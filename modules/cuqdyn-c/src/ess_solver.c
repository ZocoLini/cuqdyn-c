#include <stdlib.h>
#include <unistd.h>

#include <method_module/structure_paralleltestbed.h>
#include "method_module/solversinterface.h"
#include "output/output.h"

#include "ess_solver.h"

#include <../include/functions.h>

#include "cuqdyn.h"
#if defined(MPI2) || defined(MPI)
#include <mpi.h>
#endif

#ifdef OPENMP
#include <omp.h>
#endif

N_Vector execute_ess_solver(const char *file, const char *path, N_Vector texp, SUNMatrix yexp,
    N_Vector initial_condition, N_Vector initial_params)
{
    int error, NPROC_OPENMP;
    experiment_total *exptotal;
    result_solver result;
    int first, init;

    int nproc;
    int rank;

#if defined(MPI2) || defined(MPI)
    MPI_Comm_size(MPI_COMM_WORLD, &nproc);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
#else
    nproc = 1;
    rank = 0;
#endif

#ifdef OPENMP
#pragma omp parallel
    {
        NPROC_OPENMP = omp_get_num_threads();
    }

    exptotal = (experiment_total *) malloc(NPROC_OPENMP * sizeof(experiment_total));
    init = 1;
    for (int i = 0; i < NPROC_OPENMP; i++)
    {
        // PARSE THE OPTIONS OF THE SOLVER
        create_expetiment_struct(file, &(exptotal[i]), nproc, rank, path, init, texp, yexp, initial_condition);
        if (initial_params != NULL)
        {
            for (int i = 0; i < NV_LENGTH_S(initial_params); i++)
            {
                exptotal[0].test.bench.X0[0][i] = NV_Ith_S(initial_params, i);
            }
        }
        init = 0;
    }

    // INIT MESSAGE
    if ((rank == 0))
    {
        init_message(nproc, &(exptotal[0]), NPROC_OPENMP);
    }
    // INIT BENCHMARK
    // first = 1;
    // for (int i = 0; i < NPROC_OPENMP; i++)
    // {
    //     func = setup_benchmark(&(exptotal[i]), rank, &first);
    // }

    init_result_data(&result, exptotal[0].test.bench.dim);

#else
    exptotal = (experiment_total *) malloc(sizeof(experiment_total));
    init = 1;
    create_expetiment_struct(file, &exptotal[0], nproc, rank, path, init, texp, yexp, initial_condition);

    if (initial_params != NULL)
    {
        for (int i = 0; i < NV_LENGTH_S(initial_params); i++)
        {
            printf("QASDFASDFASDFASDF\n");
            exptotal[0].test.bench.X0[0][i] = NV_Ith_S(initial_params, i);
            printf("%lf", exptotal[0].test.bench.X0[0][i]);
        }
    }

    // INIT RESULT STRUCT
    init_result_data(&result, exptotal->test.bench.dim);

#endif

    execute_Solver(exptotal, &result, ode_model_obj_func);

    destroyexp(exptotal);

    N_Vector predicted_params = New_Serial(exptotal->test.bench.dim);
    N_VSetArrayPointer(result.bestx_value, predicted_params);
    return predicted_params;
}
