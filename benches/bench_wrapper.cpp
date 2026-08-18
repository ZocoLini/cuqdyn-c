#include <iostream>
#include <papi.h>

#include "bench_options.h"
#include "nanobench.h"

extern "C" void run_benchmark(BenchOptions *options)
{
    ankerl::nanobench::Bench b;

    b.title(options->name)
            .warmup(options->warmup)
            .epochs(options->epochs)
            .relative(options->num_functions > 1)
            .minEpochIterations(30);

    if (PAPI_library_init(PAPI_VER_CURRENT) != PAPI_VER_CURRENT)
    {
        std::cerr << "Error inicializando PAPI\n";
    }

    for (int i = 0; i < options->num_functions; ++i)
    {
#define EVENTS_LEN 4
        int EventSet = PAPI_NULL;
        long long values[EVENTS_LEN] = {0};

        PAPI_create_eventset(&EventSet);
        PAPI_add_named_event(EventSet, "MEM_LOAD_RETIRED:L1_HIT");
        PAPI_add_named_event(EventSet, "MEM_LOAD_RETIRED:L1_MISS");
        PAPI_add_named_event(EventSet, "MEM_LOAD_RETIRED:L2_HIT");
        PAPI_add_named_event(EventSet, "MEM_LOAD_RETIRED:L2_MISS");

        if (PAPI_start(EventSet) != PAPI_OK)
        {
            std::cerr << "Error starting counters PAPI\n";
        }

        b.run([&] { ((void (*)(void)) options->functions[i])(); });

        if (PAPI_stop(EventSet, values) != PAPI_OK)
        {
            std::cerr << "Error stopping counters PAPI\n";
        }

        PAPI_cleanup_eventset(EventSet);
        PAPI_destroy_eventset(&EventSet);

        // std::cout << "#### Cache analysis for " << options->name << " ###\n"
        //          << "L1 cache misses: " << values[0] << ", L2 cache misses: " << values[1] << "\n"
        //          << "L1 cache hits: " << values[2] << ", L2 cache hits: " << values[3] << "\n";
    }

    PAPI_shutdown();
}
