#include "data_reader.h"

#include <math.h>
#include <nvector/nvector_serial.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cuqdyn.h"
#include "sundials/sundials_types.h"
#include "sunmatrix/sunmatrix_dense.h"

void destroy_cuqdyn_data(CuqdynData *data)
{
    if (data == NULL)
    {
        return;
    }

    N_VDestroy(data->times);
    N_VDestroy(data->initial_values);
    SUNMatDestroy(data->all_state_data);

    // observed_data aliases all_state_data when every state is measured, so
    // this one is an aliasing check rather than a NULL guard.
    if (data->observed_data != data->all_state_data)
    {
        SUNMatDestroy(data->observed_data);
    }

    free(data->observed_idx);
    memset(data, 0, sizeof(CuqdynData));
}

int read_data_file(const char *data_file, CuqdynData *data)
{
    FILE *f = fopen(data_file, "r");
    if (f == NULL)
    {
        return 1;
    }

    memset(data, 0, sizeof(CuqdynData));

    long rows, cols;
    fscanf(f, "%ld", &rows);
    fscanf(f, "%ld", &cols);

    const long n_states = cols - 1;

    data->m = rows;
    data->n_states = n_states;
    data->times = New_Serial(rows);
    data->all_state_data = NewDenseMatrix(n_states, rows);
    data->initial_values = New_Serial(n_states);
    data->observed_idx = calloc(n_states, sizeof(int));

    sunrealtype *data_t = N_VGetArrayPointer(data->times);
    long *nan_count = calloc(n_states, sizeof(long));
    double tmp;

    // Column 0 is the initial condition: needed for every state whether or not
    // it is ever measured again, and never held out, so it says nothing about
    // observability.
    fscanf(f, "%lf", &tmp);
    data_t[0] = tmp;
    sunrealtype *first_column = ((SUNMatrixContent_Dense) data->all_state_data->content)->cols[0];

    for (int j = 0; j < n_states; ++j)
    {
        fscanf(f, "%lf", &tmp);
        first_column[j] = tmp;
        NV_Ith_S(data->initial_values, j) = tmp;
    }

    // Everything after it is a measurement, or a NaN standing for its absence.
    // scanf reads NaN as a NaN double, so nothing here needs a special case.
    for (int i = 1; i < rows; ++i)
    {
        fscanf(f, "%lf", &tmp);
        data_t[i] = tmp;
        sunrealtype *data_yi = ((SUNMatrixContent_Dense) data->all_state_data->content)->cols[i];

        for (int j = 0; j < n_states; ++j)
        {
            fscanf(f, "%lf", &tmp);
            data_yi[j] = tmp;

            if (isnan(tmp))
            {
                nan_count[j]++;
            }
        }
    }

    fclose(f);

    for (long j = 0; j < n_states; ++j)
    {
        if (isnan(NV_Ith_S(data->initial_values, j)))
        {
            fprintf(stderr, "ERROR: state y%ld has no initial value at t=0\n", j + 1);
            free(nan_count);
            destroy_cuqdyn_data(data);
            return 1;
        }

        /*
         * A state is measured at every point after t=0 or at none of them; the
         * format has no way to express a gap. Checking it is what stops a
         * single stray NaN from quietly demoting a state to unobserved and
         * discarding every real measurement it had.
         */
        if (nan_count[j] != 0 && nan_count[j] != rows - 1)
        {
            fprintf(stderr,
                    "ERROR: state y%ld mixes %ld NaN with %ld values after t=0. A state is either measured "
                    "at every time point or at none.\n",
                    j + 1, nan_count[j], rows - 1 - nan_count[j]);
            free(nan_count);
            destroy_cuqdyn_data(data);
            return 1;
        }

        if (nan_count[j] == 0)
        {
            data->observed_idx[data->n_obs++] = (int) j;
        }
    }

    free(nan_count);

    if (data->n_obs == 0)
    {
        fprintf(stderr, "ERROR: no state is measured after t=0\n");
        destroy_cuqdyn_data(data);
        return 1;
    }

    if (data->n_obs == n_states)
    {
        // Fully observed: alias instead of copying.
        data->observed_data = data->all_state_data;
        return 0;
    }

    data->observed_data = NewDenseMatrix(data->n_obs, rows);
    for (int j = 0; j < data->n_obs; ++j)
    {
        for (long i = 0; i < rows; ++i)
        {
            SM_ELEMENT_D(data->observed_data, j, i) = SM_ELEMENT_D(data->all_state_data, data->observed_idx[j], i);
        }
    }

    return 0;
}
