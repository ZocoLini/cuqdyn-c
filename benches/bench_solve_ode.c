#include "bench_options.h"
#include "bench_wrapper.h"
#include "config.h"

int main()
{
    CuqDynContext context = init_cuqdyn_context_from_file("");

    BenchFunc funcs[] = {};

    BenchOptions *options = create_bench_options("Solve ODE", funcs, sizeof(funcs) / sizeof(funcs[0]));

    run_benchmark(options);

    destroy_cuqdyn_context(context);

    return 0;
}
