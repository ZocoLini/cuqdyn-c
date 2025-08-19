#include "data_reader.h"

#include <nvector/nvector_serial.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#include "cuqdyn.h"
#include "sundials/sundials_types.h"
#include "sunmatrix/sunmatrix_dense.h"

int read_data_file(const char *data_file, N_Vector *t, ObservedData *y)
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

int read_txt_data_file(const char *data_file, N_Vector *t, TransposedObservedData *y)
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

    *y = NewDenseMatrix(cols - 1, rows);

    double tmp;

    for (int i = 0; i < rows; ++i)
    {
        fscanf(f, "%lf", &tmp);
        data_t[i] = tmp;
        sunrealtype *data_yi = ((SUNMatrixContent_Dense) (*y)->content)->cols[i];
        for (int j = 0; j < cols - 1; ++j)
        {
            fscanf(f, "%lf", &tmp);
            data_yi[j] = tmp;
        }
    }

    fclose(f);
    return 0;
}
