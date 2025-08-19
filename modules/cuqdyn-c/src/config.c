#include "config.h"

#include <unistd.h>

static CuqDynContext context = NULL;

extern CuqDynContext build_cuqdyn_context_from_file(const char *filename);

CuqDynContext init_cuqdyn_context_from_file(const char *filename)
{
    context = build_cuqdyn_context_from_file(filename);
    return context;
}

CuqDynContext get_cuqdyn_context() { return context; }
