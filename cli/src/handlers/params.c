#include <matio.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <sundials/sundials_matrix.h>
#include <unistd.h>

#include "handlers.h"
#include "lib.h"

int handle_params(int argc, char *argv[]);
int read_txt_data_file(const char *data_file, N_Vector *t, SUNMatrix *y);
int read_mat_data_file(const char *data_file, N_Vector *t, SUNMatrix *y);

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

    while ((opt = getopt(argc, argv, "d")) != -1) {
        switch (opt) {
            case 'd':
                data_file = optarg;
            break;
            default:
                fprintf(stderr, "Usage: %s -d <data-file>\n", argv[0]);
            return 1;
        }
    }

    N_Vector t = NULL;
    SUNMatrix y = NULL;

    if (read_txt_data_file(data_file, &t, &y) != 0
        || read_mat_data_file(data_file, &t, &y) != 0)
    {
        fprintf(stderr, "Error reading data file: %s\n", data_file);
        return 1;
    }

    return 0;

}

int read_txt_data_file(const char *data_file, N_Vector *t, SUNMatrix *y)
{
    // TODO: Implement reading from a text file
    FILE *f = fopen(data_file, "r");

    if (f == NULL)
    {
        return 1;
    }

    // Reading each not empty line n double values m times
    int n = 0;
    int m = 0;
    char line[1024];
    while (fgets(line, sizeof(line), f))
    {
        if (line[0] == '\n')
            continue;

        n++;
        char *ptr = line;
        while (*ptr != '\0')
        {
            if (*ptr == ' ')
                m++;
            ptr++;
        }
        m++;
    }

    fclose(f);
    return 0;
}

int read_mat_data_file(const char *data_file, N_Vector *t, SUNMatrix *y)
{
    mat_t *matfp = Mat_Open(data_file, MAT_ACC_RDONLY);
    if (matfp == NULL)
    {
        return 1;
    }

    matvar_t *matvar = Mat_VarReadNext(matfp);
    if (matvar == NULL)
    {
        fprintf(stderr, "Error reading matlab data from file: %s\n", data_file);
        return 1;
    }

    if (matvar->rank != 2)
    {
        fprintf(stderr, "Error: Data must be 2D\n");
        return 1;
    }

    if (matvar->data_type != MAT_T_DOUBLE)
    {
        fprintf(stderr, "Error: Data must be double\n");
        return 1;
    }

    const size_t rows = matvar->dims[0];
    const size_t cols = matvar->dims[1];

    if (rows < 2 || cols < 2)
    {
        fprintf(stderr, "Error: Data must be at least 2x2\n");
        return 1;
    }

    *t = N_VNew_Serial((sunindextype) rows, get_sun_context());
    sunrealtype *data_t = N_VGetArrayPointer(*t);

    // The first column of the matrix is the time vector
    *y = SUNDenseMatrix(
        (sunindextype) rows,
        (sunindextype) cols - 1,
        get_sun_context());
    sunrealtype *data_y = SUNDenseMatrix_Column(*y, 0);

    double *file_data = matvar->data;

    for (int i = 0; i < rows; ++i)
    {
        data_t[0] = file_data[i * cols];

        // Data cols start at index 1. Index 0 is the time vector
        for (int j = 1; j < cols; ++j)
        {
            data_y[i * cols + j - 1] = file_data[i * cols + j];
        }
    }

    Mat_VarFree(matvar);
    Mat_Close(matfp);
    return 0;
}