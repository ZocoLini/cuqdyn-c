//
// Created by borja on 12/06/25.
//
#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "cuqdyn.h"
#include "sundials/sundials_matrix.h"
#include "sundials/sundials_types.h"

extern void eval_states_transformer_expr(sunrealtype *input, sunrealtype *output, CuqDynContext context);

ObservablesTransposedStates transform_states(TransposedStates transposed_states)
{
    CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());

    if (conf->states_transformer.count == 0)
    {
        return transposed_states;
    }

    const int rows = SM_ROWS_D(transposed_states);
    const int cols = SM_COLUMNS_D(transposed_states);

    ObservablesTransposedStates transposed_result = NewDenseMatrix(conf->states_transformer.count, cols);

    for (int i = 0; i < cols; ++i)
    {
        sunrealtype *input = SM_COLUMN_D(transposed_states, i);
        sunrealtype *dest = SM_COLUMN_D(transposed_result, i);

        eval_states_transformer_expr(input, dest, get_cuqdyn_context());
    }

    SUNMatDestroy(transposed_states);

    return transposed_result;
}
