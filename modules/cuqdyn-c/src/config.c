#include "config.h"

#include <stdio.h>

static CuqdynConf *config = NULL;

void parse_config_file(const char *filename, CuqdynConf **config);

CuqdynConf* create_cuqdyn_conf(Tolerances tolerances, TimeConstraints time_constraints)
{
    CuqdynConf *cuqdyn_conf = malloc(sizeof(CuqdynConf));
    cuqdyn_conf->tolerances = tolerances;
    cuqdyn_conf->time_constraints = time_constraints;
    return cuqdyn_conf;
}

void destroy_cuqdyn_conf(CuqdynConf *cuqdyn_conf)
{
    if (cuqdyn_conf == NULL)
    {
        fprintf(stderr, "WARNING: Trying to free NULL Cuqdyn pointer");
        return;
    }

    destroy_tolerances(cuqdyn_conf->tolerances);
    free(cuqdyn_conf);
}

CuqdynConf* init_cuqdyn_conf_from_file(const char *filename)
{
    CuqdynConf *tmp_config = malloc(sizeof(CuqdynConf));
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

void parse_config_file(const char *filename, CuqdynConf **config)
{
    *config = NULL;
}

void set_cuqdyn_conf(CuqdynConf *cuqdyn_conf)
{
    if (config != NULL)
    {
        destroy_cuqdyn_conf(cuqdyn_conf);
    }

    config = cuqdyn_conf;
}

CuqdynConf* get_cuqdyn_conf()
{
    if (config == NULL)
    {
        fprintf(stderr, "ERROR: cuqdyn config not initialized. Call init_cuqdyn_conf_from_file() first.\n");
        exit(1);
    }

    return config;
}
