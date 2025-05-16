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

    fprintf(stdout, "%d\n", conf->ode_expr.y_count);
    fprintf(stdout, "%s\n", conf->ode_expr.exprs[0]);
    fprintf(stdout, "%s\n", conf->ode_expr.exprs[1]);
    assert(2 == conf->ode_expr.y_count);
    assert(4 == conf->ode_expr.p_count);

    return 0;
}
