#include "bench_options.h"
#include <stdlib.h>
#include <string.h>

BenchOptions *create_bench_options(char *name, BenchFunc *functions, int num_functions)
{
    BenchOptions *options = (BenchOptions *) malloc(sizeof(BenchOptions));
    options->name = strdup(name);
    options->functions = functions;
    options->num_functions = num_functions;

    options->warmup = 100;
    options->epochs = 50;

    return options;
}

void destroy_bench_options(BenchOptions *options)
{
    free(options->name);
    free(options);
}