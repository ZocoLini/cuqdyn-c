#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <unistd.h>

#include "handlers/handlers.h"
#include "handlers/solve.h"

#include <config.h>
#include <stdlib.h>
#include <string.h>

#include "cuqdyn.h"
#include "functions/lotka_volterra.h"

#ifdef MPI2
#include <mpi.h>
#endif

int handle_solve(int argc, char *argv[]);
void print_matrix(DlsMat mat, FILE *output_file, char *name);
void print_vector(N_Vector vec, FILE *output_file, char *name);

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
    FunctionType function_type = NONE;

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
            case 'f':
            {
                int function_type_int = atoi(optarg);
                function_type = create_function_type(function_type_int);
                break;
            }
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

    if (init_cuqdyn_conf_from_file(cuqdyn_config_file) == NULL)
    {
        fprintf(stderr, "ERROR: Failed to read cuqdyn config file %s\n", cuqdyn_config_file);
        return 1;
    }

#ifdef MPI2
    int err = MPI_Init(&argc, &argv);

    if (err != MPI_SUCCESS)
    {
        fprintf(stderr, "MPI_Init failed\n");
        exit(1);
    }

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

    CuqdynResult *cuqdyn_result = cuqdyn_algo(function_type, data_file, sacess_config_file, output_dir, rank, nproc);

#ifdef MPI2
    MPI_Finalize();
#endif

    N_Vector params_median = cuqdyn_result->predicted_params_median;
    DlsMat data_median = cuqdyn_result->predicted_data_median;

    DlsMat q_low = cuqdyn_result->q_low;
    DlsMat q_up = cuqdyn_result->q_up;
    N_Vector times = cuqdyn_result->times;

    char *output_file_path = malloc(strlen(output_dir) + strlen("/cuqdyn-results.txt") + 1);
    strcpy(output_file_path, output_dir);
    strcat(output_file_path, "/cuqdyn-results.txt");

    FILE *output_file = fopen(output_file_path, "w");

    print_vector(params_median, output_file, "Params");
    print_matrix(data_median, output_file, "Data");
    print_matrix(q_low, output_file, "Q_low");
    print_matrix(q_up, output_file, "Q_up");
    print_vector(times, output_file, "Times");

    free(output_file_path);
    destroy_cuqdyn_result(cuqdyn_result);

    return 0;
}

void print_matrix(DlsMat mat, FILE *output_file, char *name)
{
    fprintf(output_file, "[%s]\n", name);
    fprintf(output_file, "%ld %ld\n", SM_ROWS_D(mat), SM_COLUMNS_D(mat));

    for (int i = 0; i < SM_ROWS_D(mat); i++)
    {
        for (int j = 0; j < SM_COLUMNS_D(mat); j++)
        {
            fprintf(output_file, "%lf ", SM_ELEMENT_D(mat, i, j));
        }
        fprintf(output_file, "\n");
    }
}

void print_vector(N_Vector vec, FILE *output_file, char *name)
{
    fprintf(output_file, "[%s]\n", name);
    fprintf(output_file, "%ld\n", NV_LENGTH_S(vec));
    for (int i = 0; i < NV_LENGTH_S(vec); i++)
    {
        fprintf(output_file, "%lf ", NV_Ith_S(vec, i));
    }
    fprintf(output_file, "\n");
}
