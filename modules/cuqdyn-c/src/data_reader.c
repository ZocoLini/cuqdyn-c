#include "data_reader.h"


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
        printf("Support for .mat files has been removed in version 0.6.0");
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
    sunrealtype *data_t = N_VGetArrayPointer(*t);

    *y = NewDenseMatrix(rows, cols - 1);
    sunrealtype *data_y = ((SUNMatrixContent_Dense)(*y)->content)->data;

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
