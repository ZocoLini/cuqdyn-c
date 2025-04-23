#include <data_reader.h>
#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <unistd.h>

#include "handlers/handlers.h"
#include "handlers/solve.h"

#include "cuqdyn.h"
#include "functions/lotka_volterra.h"
#include "matlab.h"

int handle_solve(int argc, char *argv[]);

Handler create_solve_handler()
{
    Handler handler;
    handler.handle = handle_solve;
    return handler;
}

int handle_solve(int argc, char *argv[])
{
    int opt;
    char *data_file = NULL;
    char *cuqdyn_config_file = NULL;
    char *sacess_config_file = NULL;
    char *output_dir = NULL;

    while ((opt = getopt(argc, argv, "d:")) != -1)
    {
        switch (opt)
        {
            case 'd':
                data_file = optarg;
                break;
            case 'c':
                cuqdyn_config_file = optarg;
                break;
            case 's':
                sacess_config_file = optarg;
                break;
            case 'o':
                output_dir = optarg;
                break;
            default:
                fprintf(stderr, "ERROR: Wrong arguments, do %s help to see how to use it\n", argv[0]);
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
    const TimeConstraints time_constraints =
            create_time_constraints(NV_Ith_S(t, 1), NV_Ith_S(t, t_len - 1), NV_Ith_S(t, 1) - NV_Ith_S(t, 0));
    const Tolerances tolerances =
            create_tolerances(SUN_RCONST(1e-08), (realtype[]) {SUN_RCONST(1e-08), SUN_RCONST(1e-08)}, ode_model);

#ifdef MPI2
    int err = MPI_Init(&argc, &argv);

    if (err != MPI_SUCCESS)
    {
        fprintf(stderr, "MPI_Init failed\n");
        exit(1);
    }
#endif

    predict_parameters(t, y, ode_model, time_constraints, tolerances);

    return 0;
}
