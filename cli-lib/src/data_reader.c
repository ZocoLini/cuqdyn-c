#include <matio.h>
#include <nvector/nvector_serial.h>
#include <stddef.h>
#include <stdio.h>

#include "lib.h"

int read_txt_data_file(const char *data_file, N_Vector *t, SUNMatrix *y, sunrealtype *t0, N_Vector *y0)
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

int read_mat_data_file(const char *data_file, N_Vector *t, SUNMatrix *y, sunrealtype *t0, N_Vector *y0)
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

    // The first column of the matrix is the time vector
    // The first row of the matrix are the initial values [t0 y10 y20 ...]

    *t = N_VNew_Serial((sunindextype) rows - 1, get_sun_context());
    sunrealtype *data_t = N_VGetArrayPointer(*t);

    *y0 = N_VNew_Serial((sunindextype) cols - 1, get_sun_context());
    sunrealtype *data_y0 = N_VGetArrayPointer(*y0);

    *y = SUNDenseMatrix(
        (sunindextype) rows - 1,
        (sunindextype) cols - 1,
        get_sun_context());
    sunrealtype *data_y = SUNDenseMatrix_Data(*y);

    const double *file_data = matvar->data;

    *t0 = file_data[0];

    for (int j = 1; j < cols; ++j)
    {
        data_y0[j - 1] = file_data[j * rows];
    }

    for (int i = 1; i < rows; ++i)
    {
        data_t[i - 1] = file_data[i];
        for (int j = 1; j < cols; ++j)
        {
            data_y[(j - 1) * rows + i - 1] = file_data[j * rows + i];
        }
    }

    Mat_VarFree(matvar);
    Mat_Close(matfp);
    return 0;
}
