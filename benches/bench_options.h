#ifndef BENCH_OPTIONS_H
#define BENCH_OPTIONS_H

typedef void (*BenchFunc)(void);

typedef struct
{
    char *name;
    BenchFunc *functions;
    int num_functions;

    int warmup;
    int epochs;

} BenchOptions;

BenchOptions *create_bench_options(char *name, BenchFunc *functions, int num_functions);
void destroy_bench_options(BenchOptions *options);

#endif //EDO_OPTIONS_H
