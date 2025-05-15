#include <assert.h>
#include <config.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include "cuqdyn.h"

int main(void)
{
    char *config_file = "data/lotka_volterra_cuqdyn_config.xml";

    CuqdynConf *conf = malloc(sizeof(CuqdynConf));
    parse_cuqdyn_conf(config_file, conf);

    assert(2 == NV_LENGTH_S(conf->tolerances.atol));

    assert(1e-9 == NV_Ith_S(conf->tolerances.atol, 0));
    assert(1e-10 == NV_Ith_S(conf->tolerances.atol, 1));

    assert(1e-8 == conf->tolerances.rtol);

    fprintf(stdout, "%d\n", conf->tolerances.odes_count);
    fprintf(stdout, "%s\n", conf->tolerances.odes[0]);
    fprintf(stdout, "%s\n", conf->tolerances.odes[1]);
    assert(2 == conf->tolerances.odes_count);

    return 0;
}
