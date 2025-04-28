#include "config.h"

#include <stdio.h>
#include <stdlib.h>

static CuqdynConf *config = NULL;

void parse_config_file(const char *filename, CuqdynConf **config);

CuqdynConf* create_cuqdyn_conf(Tolerances tolerances, TimeConstraints time_constraints)
{
    CuqdynConf *cuqdyn_conf = malloc(sizeof(CuqdynConf));
    cuqdyn_conf->tolerances = tolerances;
    cuqdyn_conf->time_constraints = time_constraints;
    return cuqdyn_conf;
}

void destroy_cuqdyn_conf()
{
    if (config == NULL)
    {
        return;
    }

    // TODO: This frees causes a double free error somehow
    // destroy_tolerances(config->tolerances);
    // free(config);
    config = NULL;
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
    return config;
}

void parse_config_file(const char *filename, CuqdynConf **config)
{
    *config = NULL;
}

CuqdynConf *init_cuqdyn_conf(Tolerances tolerances, TimeConstraints time_constraints)
{
    destroy_cuqdyn_conf();

    config = create_cuqdyn_conf(tolerances, time_constraints);
    return config;
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

TimeConstraints create_time_constraints(realtype first_output_time, realtype tf, realtype tinc)
{
    TimeConstraints time_constraints;
    time_constraints.tf = tf;
    time_constraints.tinc = tinc;
    time_constraints.first_output_time = first_output_time;
    return time_constraints;
}

int time_constraints_steps(TimeConstraints constraints)
{
    return (int) ((constraints.tf - constraints.first_output_time) / constraints.tinc) + 1;
}

Tolerances create_tolerances(realtype scalar_rtol, N_Vector atol)
{
    Tolerances tolerances;
    tolerances.scalar_rtol = scalar_rtol;
    tolerances.abs_tol = atol;
    return tolerances;
}

void destroy_tolerances(Tolerances tolerances)
{
    N_VDestroy(tolerances.abs_tol);
}
