#include "data_reader.h"


#include <matio.h>
#include <nvector/nvector_serial.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "../include/cuqdyn.h"

int read_data_file(const char *data_file, N_Vector *t, SUNMatrix *y)
{
    const char *ext = strrchr(data_file, '.');

    if (ext && strcmp(ext, ".txt") == 0)
    {
        return read_txt_data_file(data_file, t, y);
    }

    if (ext && strcmp(ext, ".mat") == 0)
    {
        return read_mat_data_file(data_file, t, y);
    }

    return 1;
}

int read_txt_data_file(const char *data_file, N_Vector *t, SUNMatrix *y)
{
    const char *ext = strrchr(data_file, '.');
    if (ext && strcmp(ext, ".txt") != 0)
    {
        return 1;
    }

    FILE *f = fopen(data_file, "r");
    if (f == NULL)
    {
        return 1;
    }

    long rows, cols;
    fscanf(f, "%ld", &rows);
    fscanf(f, "%ld", &cols);

    *t = New_Serial(rows);
    sunsunrealtype *data_t = N_VGetArrayPointer(*t);

    *y = NewDenseMatrix(rows, cols - 1);
    sunsunrealtype *data_y = ((SUNMatrixContent_Dense)(*y)->content)->data;

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

    *t = New_Serial((long) rows);
    sunsunrealtype *data_t = N_VGetArrayPointer(*t);

    *y = NewDenseMatrix((long) rows, (long) cols - 1);
    sunsunrealtype *data_y = ((SUNMatrixContent_Dense)(*y)->content)->data;

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
