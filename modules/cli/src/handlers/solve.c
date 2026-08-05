#include "handlers/solve.h"

#include <config.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>
#include <unistd.h>

#include "cuqdyn.h"
#include "handlers/handlers.h"

#if defined(MPI) || defined(MPI2)
#include <mpi.h>
#endif

int handle_solve(int argc, char *argv[]);
void print_matrix(SUNMatrix mat, FILE *output_file, char *name);
void print_transposed_matrix(TransposedStates mat, FILE *output_file, char *name);
void print_vector(N_Vector vec, FILE *output_file, char *name);
void print_observed_idx(const CuqdynResult *result, FILE *output_file);

Handler create_solve_handler()
{
    Handler handler;
    handler.handle = handle_solve;
    return handler;
}

int handle_solve(int argc, char *argv[])
{
    int opt;
    char *data_file = NULL;
    char *cuqdyn_config_file = NULL;
    char *sacess_config_file = NULL;
    char *output_dir = NULL;

    while ((opt = getopt(argc, argv, "d:c:s:o:f:")) != -1)
    {
        switch (opt)
        {
            case 'd':
                data_file = optarg;
                break;
            case 'c':
                cuqdyn_config_file = optarg;
                break;
            case 's':
                sacess_config_file = optarg;
                break;
            case 'o':
                output_dir = optarg;
                break;
            default:
                fprintf(stderr, "ERROR: Wrong arguments, do %s help to see how to use it\n", argv[0]);
                return 1;
        }
    }

    if (cuqdyn_config_file == NULL)
    {
        fprintf(stderr, "ERROR: cuqdyn config file not specified. Use -c option.\n");
        return 1;
    }

    if (output_dir == NULL)
        output_dir = "output/";

    if (data_file == NULL)
    {
        fprintf(stderr, "ERROR: Data file not specified. Use -d option.\n");
        return 1;
    }

    if (sacess_config_file == NULL)
    {
        fprintf(stderr, "ERROR: sacess config file not specified. Use -s option.\n");
        return 1;
    }

    if (init_cuqdyn_context_from_file(cuqdyn_config_file) == NULL)
    {
        fprintf(stderr, "ERROR: Failed to read cuqdyn config file %s\n", cuqdyn_config_file);
        return 1;
    }

#if defined(MPI) || defined(MPI2)
    int err = MPI_Init(&argc, &argv);

    if (err != MPI_SUCCESS)
    {
        fprintf(stderr, "MPI_Init failed\n");
        exit(1);
    }
#endif

#ifdef MPI
    int rank, nproc;
    err = MPI_Comm_size(MPI_COMM_WORLD, &nproc);

    if (err != MPI_SUCCESS)
    {
        fprintf(stderr, "MPI_COMM_WORLD failed\n");
        exit(1);
    }

    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
#else
    int rank = 0;
    int nproc = 1;
#endif

    CuqdynResult *cuqdyn_result = cuqdyn_algo(data_file, sacess_config_file, output_dir);

    if (cuqdyn_result == NULL)
    {
#ifdef MPI
        MPI_Finalize();
#endif
        return rank == 0 ? 1 : 0;
    }

    if (rank == 0)
    {

        N_Vector params_median = cuqdyn_result->predicted_params_median;
        TransposedStates data_median = cuqdyn_result->predicted_data_median;

        SUNMatrix q_low = cuqdyn_result->q_low;
        SUNMatrix q_up = cuqdyn_result->q_up;
        N_Vector times = cuqdyn_result->times;

        char *output_file_path = malloc(strlen(output_dir) + strlen("/cuqdyn-results.txt") + 1);
        strcpy(output_file_path, output_dir);
        strcat(output_file_path, "/cuqdyn-results.txt");

        FILE *output_file = fopen(output_file_path, "w");
        if (output_file == NULL)
        {
            fprintf(stderr, "ERROR: cannot write to %s\n", output_file_path);
            free(output_file_path);
            return 1;
        }

        print_vector(params_median, output_file, "Params");
        print_transposed_matrix(data_median, output_file, "Data");
        print_matrix(q_low, output_file, "Q_low");
        print_matrix(q_up, output_file, "Q_up");
        print_vector(times, output_file, "Times");

        // CUQDyn1_Plus additions. Observed states carry conformal bands and the
        // rest delta-method ones, so the reader needs to know which is which.
        print_observed_idx(cuqdyn_result, output_file);

        if (cuqdyn_result->parameters_init != NULL)
        {
            print_vector(cuqdyn_result->parameters_init, output_file, "ParamsInit");
        }
        if (cuqdyn_result->media_tot != NULL)
        {
            print_transposed_matrix(cuqdyn_result->media_tot, output_file, "MediaTot");
        }
        if (cuqdyn_result->cov_p != NULL)
        {
            print_matrix(cuqdyn_result->cov_p, output_file, "CovP");
        }
        if (cuqdyn_result->std_y != NULL)
        {
            print_transposed_matrix(cuqdyn_result->std_y, output_file, "StdY");
        }
        // Only present with the hybrid covariance: the plain FIM bands, so a
        // reader can draw both and compare them.
        if (cuqdyn_result->q_low_alt != NULL)
        {
            print_matrix(cuqdyn_result->q_low_alt, output_file, "Q_low_fim");
            print_matrix(cuqdyn_result->q_up_alt, output_file, "Q_up_fim");
        }
        if (cuqdyn_result->loo_params != NULL)
        {
            print_matrix(cuqdyn_result->loo_params, output_file, "LooParams");
        }
        if (cuqdyn_result->resid_loo != NULL)
        {
            print_matrix(cuqdyn_result->resid_loo, output_file, "ResidLoo");
        }

        fclose(output_file);
        fprintf(stdout, "Results written to %s\n", output_file_path);

        free(output_file_path);
        destroy_cuqdyn_result(cuqdyn_result);
    }

#ifdef MPI
    MPI_Finalize();
#endif

    return 0;
}

void print_matrix(SUNMatrix mat, FILE *output_file, char *name)
{
    fprintf(output_file, "[%s]\n", name);
    fprintf(output_file, "%ld %ld\n", SM_ROWS_D(mat), SM_COLUMNS_D(mat));

    for (int i = 0; i < SM_ROWS_D(mat); i++)
    {
        for (int j = 0; j < SM_COLUMNS_D(mat); j++)
        {
            fprintf(output_file, "%.17g ", SM_ELEMENT_D(mat, i, j));
        }
        fprintf(output_file, "\n");
    }
}

void print_transposed_matrix(TransposedStates mat, FILE *output_file, char *name)
{
    fprintf(output_file, "[%s]\n", name);
    fprintf(output_file, "%ld %ld\n", SM_COLUMNS_D(mat), SM_ROWS_D(mat));

    for (int i = 0; i < SM_COLUMNS_D(mat); i++)
    {
        for (int j = 0; j < SM_ROWS_D(mat); j++)
        {
            fprintf(output_file, "%.17g ", SM_ELEMENT_D(mat, j, i));
        }
        fprintf(output_file, "\n");
    }
}

/// 0-based indices of the measured states, so a reader can tell which bands are
/// conformal and which come from the delta method.
void print_observed_idx(const CuqdynResult *result, FILE *output_file)
{
    fprintf(output_file, "[ObservedIdx]\n");
    fprintf(output_file, "%d\n", result->n_obs);
    for (int i = 0; i < result->n_obs; i++)
    {
        fprintf(output_file, "%d ", result->observed_idx[i]);
    }
    fprintf(output_file, "\n");
}

void print_vector(N_Vector vec, FILE *output_file, char *name)
{
    fprintf(output_file, "[%s]\n", name);
    fprintf(output_file, "%ld\n", NV_LENGTH_S(vec));
    for (int i = 0; i < NV_LENGTH_S(vec); i++)
    {
        fprintf(output_file, "%.17g ", NV_Ith_S(vec, i));
    }
    fprintf(output_file, "\n");
}
