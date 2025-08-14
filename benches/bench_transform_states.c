#include <states_transformer.h>
#include <sunmatrix/sunmatrix_dense.h>
#include "config.h"
#include "cuqdyn.h"

#define CUQDYN_CONF "../tests/data/nfkb_cuqdyn_config.xml"

void bench_transform_states();
extern void run_benchmark(void (*func)(void));

int main()
{
    CuqDynContext context = init_cuqdyn_context_from_file(CUQDYN_CONF);
    CuqdynConf *conf = get_cuqdyn_conf(context);

    run_benchmark(bench_transform_states);

    return 0;
}

void bench_transform_states()
{
    #define STATES_ROWS 12
    #define STATES_COLS 16

    sunrealtype states_values[STATES_ROWS][STATES_COLS] = {
        0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        5, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        6, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        7, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        8, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        9, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        10, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        11, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
    };

    SUNMatrix states = NewDenseMatrix(STATES_ROWS, STATES_COLS);

    for (int i = 0; i < STATES_ROWS; ++i) {
        for (int j = 0; j < STATES_COLS; ++j) {
            SM_ELEMENT_D(states, i, j) = states_values[i][j];
        }
    }

    SUNMatrix transformed_states = transform_states(states);

    SUNMatDestroy(transformed_states);
}
