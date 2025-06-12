//
// Created by borja on 12/06/25.
//
#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "matlab.h"

extern void eval_states_transformer_expr(sunrealtype *input, sunrealtype *output);

SUNMatrix transform_states(SUNMatrix states)
{
    CuqdynConf *conf = get_cuqdyn_conf();

    if (conf->states_transformer.count == 0)
    {
        return states;
    }

    const int rows = SM_ROWS_D(states);
    const int cols = SM_COLUMNS_D(states);

    SUNMatrix transformed_result = NewDenseMatrix(rows, conf->states_transformer.count + 1); // + 1 adds the time column

    for (int i = 0; i < rows; ++i)
    {
        N_Vector input = copy_matrix_row(states, i, 1, cols);
        sunrealtype *output = malloc(conf->states_transformer.count * sizeof(sunrealtype));

        eval_states_transformer_expr(NV_DATA_S(input), output);

        SM_ELEMENT_D(transformed_result, i, 0) = SM_ELEMENT_D(states, i, 0);
        for (int j = 0; j < conf->states_transformer.count; ++j)
        {
            SM_ELEMENT_D(transformed_result, i, j + 1) = NV_Ith_S(input, j);
        }

        N_VDestroy(input);
        free(output);
    }

    SUNMatDestroy(states);
    return transformed_result;
}