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

    BenchOptions *options = create_bench_options("Transform States", funcs, sizeof(funcs) / sizeof(funcs[0]));

    run_benchmark(options);

    return 0;
}

#define STATES_ROWS 1000
#define STATES_COLS 16

void bench_transform_states()
{
    sunrealtype states_values[STATES_ROWS][STATES_COLS] = { 0 };

    TransposedStates states = NewDenseMatrix(STATES_COLS, STATES_ROWS);

    for (int i = 0; i < STATES_ROWS; ++i)
    {
        for (int j = 0; j < STATES_COLS; ++j)
        {
            SM_ELEMENT_D(states, j, i) = states_values[i][j];
        }
    }

    ObservablesTransposedStates transformed_states = transform_states(states);

    SUNMatDestroy(transformed_states);
}
