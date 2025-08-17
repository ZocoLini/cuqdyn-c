#include <assert.h>
#include <sunmatrix/sunmatrix_dense.h>
#include "config.h"
#include "cuqdyn.h"
#include "states_transformer.h"

#define CUQDYN_CONF "data/nfkb_cuqdyn_config.xml"

int main()
{
    CuqDynContext context = init_cuqdyn_context_from_file(CUQDYN_CONF);
    CuqdynConf *conf = get_cuqdyn_conf(context);

    sunrealtype states_values[] = {
        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
    };
    sunrealtype expected_transformation_values[] = {
        0, 1, 2, 1, 3, 1, 1,
        1, 2, 4, 2, 6, 2, 2
    };

    assert(6 == conf->states_transformer.count);

    TransposedStates states = NewDenseMatrix(16, 2);

    for (int i = 0; i < 2; ++i) {
        for (int j = 0; j < 16; ++j) {
            SM_ELEMENT_D(states, j, i) = states_values[16 * i + j];
        }
    }

    ObservablesTransposedStates transformation = transform_states(states);

    assert(SM_ROWS_D(transformation) == 7);    
    assert(SM_COLUMNS_D(transformation) == 2);    
    
    for (int i = 0; i < 2; ++i) {
        for (int j = 0; j < 7; ++j) {
            
            assert(expected_transformation_values[7 * i + j] == SM_ELEMENT_D(transformation, j, i));
        }
    }

    destroy_cuqdyn_context(context);
    SUNMatDestroy(transformation);

    return 0;
}
