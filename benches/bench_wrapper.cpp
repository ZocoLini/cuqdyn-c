#include "nanobench.h"

extern "C" void run_benchmark(void (*c_function)(void))
{
    ankerl::nanobench::Bench b;

    b.title("Random Number Generators")
            .warmup(100)
            .epochs(50);

    b.performanceCounters(true);

    b.run([&] { c_function(); });
}
