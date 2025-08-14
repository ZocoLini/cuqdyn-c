#include "nanobench.h"
#include "bench_options.h"

extern "C" void run_benchmark(BenchOptions *options)
{
    ankerl::nanobench::Bench b;

    b.title(options->name)
            .warmup(options->warmup)
            .epochs(options->epochs)
            .relative(options->num_functions > 1);

    for (int i = 0; i < options->num_functions; ++i)
    {
        b.run([&] { ((void (*)(void)) options->functions[i])(); });
    }
}
