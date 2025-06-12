#include "data_reader.h"
#include "functions.h"
#include "matlab.h"
#include "method_module/structure_paralleltestbed.h"

#define CUQDYN_CONF "data/obj_function_cuqdyn_config.xml"
#define SACESS_CONF "data/obj_function_ess_config_nl2sol.dn2fb.xml"
#define DATA "data/alpha_pinene_paper_data.txt"

int main()
{
    init_cuqdyn_conf_from_file(CUQDYN_CONF);

    N_Vector texp = NULL;
    SUNMatrix yexp = NULL;

    read_data_file(DATA, &texp, &yexp);
    N_Vector initial_values = copy_matrix_row(yexp, 0, 0, SM_COLUMNS_D(yexp));

    experiment_total *exp_total = malloc(sizeof(experiment_total));
    create_expetiment_struct(SACESS_CONF, &exp_total[0], 1, 0, "output", 1, texp, yexp, initial_values);

    double x[5] = {1.0, 1.0, 1.0, 1.0, 1.0};

    output_function *out = obj_func(x, exp_total);

    printf("VAlue %lf", out->value);

    destroyexp(exp_total);
    return 0;
}
