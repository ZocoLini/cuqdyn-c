#include <matio.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <sundials/sundials_matrix.h>
#include <unistd.h>
#include <data_reader.h>

#include "handlers.h"
#include "params.h"
#include "lib.h"

int handle_params(int argc, char *argv[]);

Handler create_params_handler()
{
    Handler handler;
    handler.handle = handle_params;
    return handler;
}

int handle_params(int argc, char *argv[])
{
    int opt;
    char *data_file = NULL;

    while ((opt = getopt(argc, argv, "d:")) != -1) {
        switch (opt) {
            case 'd':
                data_file = optarg;
            break;
            default:
                fprintf(stderr, "Usage: %s -d <data-file>\n", argv[0]);
            return 1;
        }
    }

    sunrealtype t0 = 0.0;
    N_Vector y0 = NULL;
    N_Vector t = NULL;
    SUNMatrix y = NULL;

    if (read_txt_data_file(data_file, &t, &y, &t0, &y0) != 0
        && read_mat_data_file(data_file, &t, &y, &t0, &y0) != 0)
    {
        fprintf(stderr, "Error reading data file: %s\n", data_file);
        return 1;
    }

    printf("t0 = %g\n", t0);

    printf("y0 = (");
    for (long i = 0; i < N_VGetLength(y0); i++)
    {
        printf("%g, ", NV_Ith_S(y0, i));
    }
    printf(")\n");

    for (int i = 0; i < N_VGetLength(t); i++)
    {
        printf("t[%d] = %g\n", i, NV_Ith_S(t, i));
        for (int j = 0; j < SUNDenseMatrix_Columns(y); j++)
        {
            printf("y[%d][%d] = %g\n", i, j, SM_ELEMENT_D(y, i, j));
        }
    }

    return 0;
}