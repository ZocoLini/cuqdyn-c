#include <matio.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <string.h>
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

    N_Vector t = NULL;
    SUNMatrix y = NULL;

    if (read_txt_data_file(data_file, &t, &y) != 0
        && read_mat_data_file(data_file, &t, &y) != 0)
    {
        fprintf(stderr, "Error reading data file: %s\n", data_file);
        return 1;
    }

    // Bucle para mostrar los datos
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

int read_txt_data_file(const char *data_file, N_Vector *t, SUNMatrix *y)
{
    FILE *f = fopen(data_file, "r");
    if (f == NULL)
    {
        return 1;
    }

    // TODO: Not yet implemented

    fclose(f);
    return 1;
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
    sunrealtype *data_y = SUNDenseMatrix_Data(*y);

    double *file_data = matvar->data;

    for (int i = 0; i < rows; ++i)
    {
        data_t[i] = file_data[i];
        for (int j = 1; j < cols; ++j)
        {
            data_y[(j - 1) * rows + i] = file_data[j * rows + i];
        }
    }

    Mat_VarFree(matvar);
    Mat_Close(matfp);
    return 0;
}