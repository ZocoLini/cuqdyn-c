#include <data_reader.h>
#include <matio.h>
#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <unistd.h>

#include "handlers.h"
#include "lib.h"
#include "params.h"

#include "lotka_volterra.h"
#include "matlab.h"

int handle_params(int argc, char *argv[]);

Handler create_params_handler()
{
    Handler handler;
    handler.handle = handle_params;
    return handler;
}

int handle_params(int argc, char *argv[])
{
    int opt;
    char *data_file = NULL;

    while ((opt = getopt(argc, argv, "d:")) != -1)
    {
        switch (opt)
        {
            case 'd':
                data_file = optarg;
                break;
            default:
                fprintf(stderr, "Usage: %s -d <data-file>\n", argv[0]);
                return 1;
        }
    }

    N_Vector t = NULL;
    DlsMat y = NULL;

    if (read_txt_data_file(data_file, &t, &y) != 0 && read_mat_data_file(data_file, &t, &y) != 0)
    {
        fprintf(stderr, "Error reading data file: %s\n", data_file);
        return 1;
    }

    const realtype t0 = NV_Ith_S(t, 0);
    N_Vector y0 = copy_matrix_row(y, 0, 0, SM_COLUMNS_D(y));

    const long t_len = NV_LENGTH_S(t);

    // TODO: The f shouldn't be hardcoded and there should be a function called created_lotka_volterra_ode_model
    // TODO: To much hardcoded right now
    const ODEModel ode_model = create_ode_model(2, lotka_volterra_f, y0, t0);
    const TimeConstraints time_constraints =create_time_constraints(
        NV_Ith_S(t, 1),
        NV_Ith_S(t, t_len - 1),
        NV_Ith_S(t, 1) - NV_Ith_S(t, 0)
    );
    const Tolerances tolerances =create_tolerances(
        SUN_RCONST(1e-08),
        (realtype[]) {SUN_RCONST(1e-08), SUN_RCONST(1e-08)},
        ode_model
    );

    predict_parameters(t, y, ode_model, time_constraints, tolerances);

    return 0;
}
