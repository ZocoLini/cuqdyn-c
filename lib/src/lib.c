#include "lib.h"
#include <nvector/nvector_serial.h>
#include <string.h>
#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

#include "matlab.h"
#include "ode_solver.h"

SUNContext get_sun_context()
{
    static SUNContext ctx;
    if (ctx == NULL)
    {
        SUNContext_Create(SUN_COMM_NULL, &ctx);
    }
    return ctx;
}

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
    // The original code solves the ode using this params but the result is not used again

    SUNMatrix resid_loo = SUNDenseMatrix(observed_data_rows, observed_data_cols, sunctx);
    MatrixArray predicted_data_matrix = create_matrix_array(observed_data_rows - 1);

    // TODO: This can be done in parallel and the indices can be erroneous
    for (long i = 1; i < observed_data_rows; ++i)
    {
        LongArray indices_to_remove = create_array((long[]){i + 1}, 1);

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

        matrix_array_set_index(predicted_data_matrix, i - 1, predicted_data);
    }

    // TODO: Output this matrix
    SUNMatrix median_matrix = matrix_array_get_median(predicted_data_matrix);
}

LongArray create_array(long *data, const long len)
{
    LongArray array;
    array.data = data;
    array.len = len;
    return array;
}

LongArray create_empty_array()
{
    LongArray array;
    array.data = NULL;
    array.len = 0;
    return array;
}

long array_get_index(LongArray array, long i) { return array.data[i]; }

MatrixArray create_matrix_array(long len)
{
    MatrixArray array;
    array.len = len;
    array.data = (SUNMatrix*) malloc(len * sizeof(SUNMatrix));
    return array;
}

SUNMatrix matrix_array_get_index(MatrixArray array, long i)
{
    if (i < 0 || i >= array.len)
    {
        printf("ERROR: Index out of bounds in function matrix_array_get_index()\n");
        return NULL;
    }

    return array.data[i];
}

void matrix_array_set_index(MatrixArray array, long i, SUNMatrix matrix)
{
    if (i < 0 || i >= array.len)
    {
        printf("ERROR: Index out of bounds in function matrix_array_get_index()\n");
        return;
    }

    array.data[i] = matrix;
}

int compare_sunrealtype(const void *a, const void *b)
{
    return *(sunrealtype *) a - *(sunrealtype *) b;
}

SUNMatrix matrix_array_get_median(MatrixArray matrix_array)
{
    SUNMatrix first_matrix = matrix_array_get_index(matrix_array, 0);
    sunindextype rows = SM_ROWS_D(first_matrix);
    sunindextype cols = SM_COLUMNS_D(first_matrix);

    long max_z = matrix_array.len;

    SUNMatrix medians_matrix = SUNDenseMatrix(rows, cols, get_sun_context());
    sunrealtype *medians = SM_DATA_D(medians_matrix);

    sunrealtype values[max_z];

    for (int i = 0; i < rows; ++i)
    {
        for (int j = 0; j < cols; ++j)
        {
            for (int z = 0; z < max_z; ++z)
            {
                SUNMatrix actual_matrix = matrix_array_get_index(matrix_array, z);
                values[z] = SM_DATA_D(actual_matrix)[i * cols + j];
            }

            // Sorting the vector to obtain the median easily
            qsort(values, max_z, sizeof(values[0]), compare_sunrealtype);

            medians[i * cols + j] = max_z & 0b1
                ? values[(max_z - 1) / 2]
                : (values[max_z / 2 - 1] + values[max_z / 2]) / 2;
        }
    }

    return medians_matrix;
}