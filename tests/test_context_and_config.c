#include <assert.h>
#include <stdio.h>

#include "config.h"


#define CUQDYN_CONF EXAMPLES_DIR "/logistic/cuqdyn-fim.xml"

int main()
{
    CuqDynContext context = init_cuqdyn_context_from_file(CUQDYN_CONF);

    CuqdynConf *config = get_cuqdyn_conf(context);

    assert(config->tolerances.rtol == 1e-8);
    assert(config->tolerances.atol[0] == 1e-8);
    assert(config->tolerances.atol_len == 1);

    assert(config->ode_expr.y_count == 1);
    assert(config->ode_expr.p_count == 2);

    // States and parameters are indexed from zero, as the evaluator registers them.
    char *exp_expr = "p0 * y0 * (1 - y0 / p1)";
    int i = 0;

    while (exp_expr[i] != '\0')
    {
        assert(exp_expr[i] == config->ode_expr.exprs[0][i]);
        i++;
    }

    assert(config->y0.len == 0);
    assert(config->y0.array == NULL);

    destroy_cuqdyn_context(context);

    return 0;
}
