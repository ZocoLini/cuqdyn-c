#include "config.h"

#include <stdio.h>

static cuqdyn_conf *config = NULL;

void parse_config_file(const char *filename, cuqdyn_conf **config);

cuqdyn_conf* init_cuqdyn_conf_from_file(const char *filename)
{
    cuqdyn_conf *tmp_config = malloc(sizeof(cuqdyn_conf));
    if (tmp_config == NULL)
    {
        fprintf(stderr, "ERROR: Memory allocation failed in function init_cuqdyn_conf_from_file()\n");
        exit(1);
    }

    parse_config_file(filename, &tmp_config);

    if (tmp_config == NULL)
    {
        fprintf(stderr, "ERROR: Unable to parse cuqdyn config file \"%s\"\n", filename);
        exit(1);
    }

    config = tmp_config;
    return get_cuqdyn_conf();
}

void parse_config_file(const char *filename, cuqdyn_conf **config)
{
    *config = NULL;
}

cuqdyn_conf* get_cuqdyn_conf()
{
    if (config == NULL)
    {
        fprintf(stderr, "ERROR: cuqdyn config not initialized. Call init_cuqdyn_conf_from_file() first.\n");
        exit(1);
    }

    return config;
}

void destroy_cuqdyn_conf()
{
    free(config);
}
