#include <states_transformer.h>
#include <sunmatrix/sunmatrix_dense.h>
#include "config.h"
#include "cuqdyn.h"
#include "bench_options.h"
#include "bench_wrapper.h"

#define CUQDYN_CONF "../tests/data/nfkb_cuqdyn_config.xml"

void bench_transform_states();
void bench_transform_states_2();

int main()
{
    CuqDynContext context = init_cuqdyn_context_from_file(CUQDYN_CONF);
    CuqdynConf *conf = get_cuqdyn_conf(context);

    BenchFunc funcs[] = {
        bench_transform_states,
        bench_transform_states_2
    };

    BenchOptions *options = create_bench_options("Transform States", funcs, sizeof(funcs) / sizeof(funcs[0]));

    run_benchmark(options);

    return 0;
}

#define STATES_ROWS 1000
#define STATES_COLS 16

void bench_transform_states()
{
    sunrealtype states_values[STATES_COLS][STATES_ROWS] = { 0 };

    SUNMatrix states = NewDenseMatrix(STATES_ROWS, STATES_COLS);

    for (int i = 0; i < STATES_ROWS; ++i)
    {
        for (int j = 0; j < STATES_COLS; ++j)
        {
            SM_ELEMENT_D(states, i, j) = states_values[j][i];
        }
    }

    SUNMatrix transformed_states = transform_states(states);

    SUNMatDestroy(transformed_states);
}

void bench_transform_states_2()
{
    sunrealtype states_values[STATES_ROWS][STATES_COLS] = { 0 };

    SUNMatrix states = NewDenseMatrix(STATES_COLS, STATES_ROWS);

    for (int i = 0; i < STATES_ROWS; ++i)
    {
        for (int j = 0; j < STATES_COLS; ++j)
        {
            SM_ELEMENT_D(states, j, i) = states_values[i][j];
        }
    }

    SUNMatrix transformed_states = transform_states_2(states);

    SUNMatDestroy(transformed_states);
}
