/**
 * @file solverinterface.c
 * @author David R. Penas
 * @brief File containing interface functions to load the different solver
 * implemented in the toolbox.
 */


#include <error/def_errors.h>
#include <method_module/evaluationinterface.h>
#include <method_module/structure_paralleltestbed.h>
#include <string.h>
#include <unistd.h>

#include <method_module/solversinterface.h>

#ifdef SACESS_OPENMP
#include <omp.h>
#endif


// execute solver
int execute_Solver(experiment_total *exp1, result_solver *result, void *(*function)(double *, void *) )
{
    int isparallel;
    int error;
    long maxfunevals;
    const char *systemsBiology = "systemBiology";

// NEW: The MPI build fails with SEGFAULT due to this
#ifndef MPI
    if ((strcmp(exp1->methodScatterSearch->loptions->solver, "nl2sol") == 0) &&
        (strcmp(exp1->test.bench.type, systemsBiology) != 0))
    {
        printf("WARNING: you are using nl2sol local solver. Remember you need define the residuals in the objective "
               "function code.\n\n");
    }
#endif
    maxfunevals = (long) exp1->test.max_eval;
    // OLD:
    // if (is_parallel(*exp1))
    // {
    //     isparallel = 1;
    // }
    // else
    // {
    //     isparallel = 0;
    // }

    // if (isparallel == 1)
    // {
    //     error = execute_parallel_solver(exp1, result, maxfunevals, exp1->test.VTR, function);
    // }
    // else
    // {
    //     error = execute_serial_solver(exp1, result, maxfunevals, exp1->test.VTR, function);
    // }

    // In an MPI build sacess runs over the group of ranks the caller hands each
    // run, see execution.comm. The parallel methods need more than two of them:
    // with two, one would be the master and the other its only slave. Below
    // that the first rank runs the sequential eSS alone and hands its result to
    // the others. The config itself cannot ask for it, see load_configuration_XML.
#ifdef MPI
    if (exp1->execution.NPROC > 2 && exp1->methodScatterSearch != NULL)
    {
        error = execute_parallel_solver(exp1, result, maxfunevals, exp1->test.VTR, function);
    }
    else
    {
        error = 0;
        if (exp1->execution.idp == 0)
        {
            // The sequential eSS still gathers its results over the
            // communicators, so it is shown a group of just this rank.
            const MPI_Comm group = exp1->execution.comm;
            const int nproc = exp1->execution.NPROC;

            exp1->execution.comm = MPI_COMM_SELF;
            exp1->execution.topology.comunicator = MPI_COMM_SELF;
            exp1->execution.NPROC = 1;

            error = execute_serial_solver(exp1, result, maxfunevals, exp1->test.VTR, function);

            exp1->execution.comm = group;
            exp1->execution.topology.comunicator = group;
            exp1->execution.NPROC = nproc;
        }

        MPI_Bcast(&error, 1, MPI_INT, 0, exp1->execution.comm);
        MPI_Bcast(&result->best_value, 1, MPI_DOUBLE, 0, exp1->execution.comm);
        MPI_Bcast(result->bestx_value, exp1->test.bench.dim, MPI_DOUBLE, 0, exp1->execution.comm);
    }
#else
    error = execute_serial_solver(exp1, result, maxfunevals, exp1->test.VTR, function);
#endif

    return error;
}


int execute_parallel_solver(experiment_total *exp, result_solver *result, long maxfunevals, double unused,
                            void *(*function)(double *, void *) )
{
    int error, i, idsolver;
    int id;
    int NPROC;
    id = 0;
    NPROC = exp->execution.NPROC;
#ifdef MPI
    id = exp->execution.idp;
    error = 0;
    int benchmark;
    benchmark = 0;
    const char *systemsBiology;

    systemsBiology = "systemBiology";

#ifdef SACESS_OPENMP
#pragma omp parallel
    {
        exp[0].par_st->NPROC_OPENMP = omp_get_max_threads();
    }
#endif


    if ((*exp).methodScatterSearch != NULL)
    {

        if ((strcmp((*exp).methodScatterSearch->loptions->solver, "nl2sol") == 0) &&
            (strcmp((*exp).test.bench.type, systemsBiology) != 0))
        {
            printf("WARNING: you are using nl2sol local solver. Remember you need define the residuals in the "
                   "objective function code.\n\n");
        }

        idsolver = getnumversion(exp);
        if (idsolver == 1)
        {
            if (exp->execution.NPROC > 1)
            {
#ifdef GNU
                error = __modcess_MOD_cess((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#elif defined(INTEL)
                error = modcess_mp_cess_((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#endif
            }
            else
            {
                perror(error40);
                exit(0);
            }
        }
        else if (idsolver == 2)
        {
#ifdef GNU
            error = __modacessdist_MOD_acessdist((void *) exp, function, (void *) result, &maxfunevals,
                                                 &(*exp).test.VTR);
#elif defined(INTEL)
            error = modacessdist_mp_acessdist_((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#endif
        }
        else if (idsolver == 3)
        {

            if (exp->execution.NPROC > 1)
            {
#ifdef GNU
                error = __modsacess_MOD_sacess((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#elif defined(INTEL)
                error = modsacess_mp_sacess_((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#endif
            }
            else
            {
                perror(error39);
                exit(0);
            }
        }
        else if (idsolver == 4)
        {
#ifdef GNU
            error = __modessm_MOD_essm((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#elif defined(INTEL)
            error = modessm_mp_essm_((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#endif
        }
    }


#endif
    return error;
}

int execute_serial_solver(experiment_total *exp, result_solver *result, long maxfunevals, double unused,
                          void *(*function)(double *, void *) )
{
    int error = 0;

    if ((*exp).methodScatterSearch == NULL)
        return error;

#ifdef GNU
    error = __scattersearch_MOD_sscattersearch((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#elif defined(INTEL)
    error = scattersearch_mp_sscattersearch_((void *) exp, function, (void *) result, &maxfunevals, &(*exp).test.VTR);
#endif

    return error;
}
