#include "lib.h"
#include <nvector/nvector_serial.h>
#include <string.h>
#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

#include "math.h"
#include "matlab.h"
#include "ode_solver.h"

Problem create_problem(FunctionType function_type, N_Vector lower_bounds, N_Vector upper_bounds, N_Vector parameters)
{
    Problem problem;
    problem.function_type = function_type;
    problem.lower_bounds = lower_bounds;
    problem.upper_bounds = upper_bounds;
    problem.parameters = parameters;
    return problem;
}

Options create_options(const int max_iterations, double *log_var_index, const int should_save, char solver[5])
{
    Options options;
    options.max_iterations = max_iterations;
    options.log_var_index = log_var_index;
    options.should_save = should_save;
    strcpy(options.solver, solver);
    return options;
}

Results meigo(Problem problem, Options options, N_Vector t, SUNMatrix x)
{
    // TODO: Calls MEIGO in the MATLAB code --> MEIGO(problem,opts,'ESS',texp,yexp);
}

void predict_parameters(N_Vector times, SUNMatrix observed_data, ODEModel ode_model, TimeConstraints time_constraints, Tolerances tolerances, SUNContext sunctx)
{
    sunrealtype *observed_data_ptr = SM_DATA_D(observed_data);

    sunindextype observed_data_rows = SM_ROWS_D(observed_data);
    sunindextype observed_data_cols = SM_COLUMNS_D(observed_data);
    sunindextype times_len = NV_LENGTH_S(times);

    if (times_len != observed_data_rows)
    {
        printf("ERROR: The number of rows in the observed data matrix must match the length of the times vector.\n");
        return;
    }

    N_Vector initial_values = N_VNew_Serial(observed_data_cols, sunctx);
    N_VSetArrayPointer(&observed_data_ptr[1], initial_values);

    /*
     * problem.f='prob_mod_lv';
     * problem.x_L=0.001*ones(1,4); % Lower bounds of the variables
     * problem.x_U=ones(1,4); % Upper bounds of the variables
     * problem.x_0=[0.3, 0.3, 0.3, 0.3]; % Initial points
     * opts.maxeval=3e3; % Maximum number of function evaluations (default 1000)
     * opts.log_var=[1:4]; % Indexes of the variables which will be analyzed using a logarithmic distribution instead of
     * an uniform one opts.local.solver='nl2sol'; % Local solver to perform the local search opts.inter_save=1; %  Saves
     * results of intermediate iterations in eSS_report.mat
     */

    // TODO: This doen't work yet
    Problem problem = create_problem(LOTKA_VOLTERRA, NULL, NULL, NULL);
    const Options options = create_options(3000, NULL, 0, "nl2sol");

    Results results = meigo(problem, options, times, observed_data);
    N_Vector parameters_init = results.best; // Optimal parameters
    problem.parameters = parameters_init;
    // The original code solves the ode using this params but thye result is not used again

    SUNMatrix resid_loo = SUNDenseMatrix(observed_data_rows, observed_data_cols, sunctx);
    // TODO: Create a struct to handle an array of SUNMatrix
    Array media_matrix = create_array((SUNMatrix[]){}, observed_data_rows - 1);

    // TODO: This can be done in parallel and the indices can be erroneous
    for (long i = 1; i < observed_data_rows; ++i)
    {
        Array indices_to_remove = create_array((long[]){i + 1}, 1);

        N_Vector texp = copy_vector_remove_indices(times, indices_to_remove, sunctx);
        SUNMatrix yexp = copy_matrix_remove_rows(observed_data, indices_to_remove, sunctx);

        results = meigo(problem, options, texp, yexp);
        N_Vector predicted_params = results.best;
        SUNMatrix ode_solution = solve_ode(predicted_params, ode_model, time_constraints, tolerances, sunctx);

        SUNMatrix predicted_data = copy_matrix_remove_columns(ode_solution, create_array((long[]){1}, 1), sunctx);

        for (int j = 0; j < observed_data_cols; ++j)
        {
            sunindextype actual_index = i * observed_data_cols + j;
            SM_DATA_D(resid_loo)[actual_index] = abs(SM_DATA_D(observed_data)[actual_index] - SM_DATA_D(predicted_data)[actual_index]);
        }
        
        // TODO: set_matrix_array_index(predicted_data, i - 1);
    }
}

Array create_array(long *data, const long len)
{
    Array array;
    array.data = data;
    array.len = len;
    return array;
}

Array create_empty_array()
{
    Array array;
    array.data = NULL;
    array.len = 0;
    return array;
}

long array_get_index(Array array, long i) { return array.data[i]; }
