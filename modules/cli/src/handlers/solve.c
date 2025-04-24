#include <data_reader.h>
#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <unistd.h>

#include "handlers/handlers.h"
#include "handlers/solve.h"

#include <config.h>
#include <stdlib.h>

#include "cuqdyn.h"
#include "functions/lotka_volterra.h"
#include "matlab.h"

int handle_solve(int argc, char *argv[]);

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

    while ((opt = getopt(argc, argv, "d:")) != -1)
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
                int function_type_int = atoi(optarg);
                function_type = create_function_type(function_type_int);
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
        output_dir = "output";

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
#endif

    CuqdynResult *cuqdyn_result = cuqdyn_algo(function_type, data_file, sacess_config_file, output_dir);

    // TODO: Print the results

    destroy_cuqdyn_result(cuqdyn_result);

    return 0;
}
