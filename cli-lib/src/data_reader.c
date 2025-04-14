#include <matio.h>
#include <nvector/nvector_serial.h>
#include <stddef.h>
#include <stdio.h>

#include "lib.h"

int read_txt_data_file(const char *data_file, N_Vector *t, SUNMatrix *y)
{
    FILE *f = fopen(data_file, "r");
    if (f == NULL)
    {
        return 1;
    }

    long rows, cols;
    fscanf(f, "%ld", &rows);
    fscanf(f, "%ld", &cols);

    *t = N_VNew_Serial(rows, get_sun_context());
    sunrealtype *data_t = N_VGetArrayPointer(*t);

    *y = SUNDenseMatrix(rows, cols - 1, get_sun_context());
    sunrealtype *data_y = SUNDenseMatrix_Data(*y);

    double tmp;

    for (int i = 0; i < rows; ++i)
    {
        fscanf(f, "%lf", &tmp);
        data_t[i] = tmp;
        for (int j = 0; j < cols - 1; ++j)
        {
            fscanf(f, "%lf", &tmp);
            data_y[j * rows + i] = tmp;
        }
    }

    fclose(f);
    return 0;
}

/*
 * The file should be a single matrix mxn
 * All the data contained in the matrix is the observed data and has this form:
 *      t0 y00 y01 y02 ... y0n
 *      t1 y10 y11 y12 ... y1n
 *      .                   .
 *      .                   .
 *      .                   .
 *      tm ym0 ym1 ym2 ... ymn
 *
 * The time vector is the first column of the matrix [t0, t1, t2, ..., tm]
 * The y matrix is the entire matrix skipping the first column
 *      y00 y01 y02 ... y0n
 *      y10 y11 y12 ... y1n
 *      .                .
 *      .                .
 *      .                .
 *      ym0 ym1 ym2 ... ymn
 */
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

    // The first column of the matrix is the time vector
    // The first row of the matrix are the initial values [t0 y10 y20 ...]

    *t = N_VNew_Serial((sunindextype) rows, get_sun_context());
    sunrealtype *data_t = N_VGetArrayPointer(*t);

    *y = SUNDenseMatrix(
        (sunindextype) rows,
        (sunindextype) cols - 1,
        get_sun_context());
    sunrealtype *data_y = SUNDenseMatrix_Data(*y);

    const double *file_data = matvar->data;

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
