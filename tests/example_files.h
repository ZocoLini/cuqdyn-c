#pragma once

#include <stdio.h>

#ifndef EXAMPLES_DIR
#error "EXAMPLES_DIR must point at example-files/ (set by tests/CMakeLists.txt)"
#endif

/// Path to a file inside an example folder, so a test only names the model: example_file("sir", "data.txt").
static const char *example_file(const char *model, const char *file)
{
    static char paths[4][512];
    static int next = 0;

    char *path = paths[next];
    next = (next + 1) % 4;

    snprintf(path, sizeof(paths[0]), EXAMPLES_DIR "/%s/%s", model, file);

    return path;
}

static const char *example_conf(const char *model) { return example_file(model, "cuqdyn.xml"); }

static const char *example_sacess_conf(const char *model) { return example_file(model, "sacess-serial.xml"); }

static const char *example_data(const char *model) { return example_file(model, "data.txt"); }
