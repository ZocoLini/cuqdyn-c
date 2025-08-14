#include <states_transformer.h>
#include <sunmatrix/sunmatrix_dense.h>
#include "config.h"
#include "cuqdyn.h"
#include "bench_options.h"
#include "bench_wrapper.h"

#define CUQDYN_CONF "../tests/data/nfkb_cuqdyn_config.xml"

void bench_transform_states();

int main()
{
    CuqDynContext context = init_cuqdyn_context_from_file(CUQDYN_CONF);
    CuqdynConf *conf = get_cuqdyn_conf(context);

    BenchFunc funcs[] = {
        bench_transform_states
    };

    BenchOptions *options = create_bench_options("", funcs, sizeof(funcs) / sizeof(funcs[0]));

    run_benchmark(options);

    return 0;
}

void bench_transform_states()
{
    #define STATES_ROWS 24
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
        11, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
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
        11, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
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
