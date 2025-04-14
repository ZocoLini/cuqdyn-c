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

void predict_parameters(N_Vector times, SUNMatrix data, ODEModel ode_model, TimeConstraints time_constraints,
                        Tolerances tolerances)
{
    sunindextype data_rows = SM_ROWS_D(data);
    sunindextype times_len = NV_LENGTH_S(times);

    sunindextype observed_data_rows = data_rows - 1; // The first row is the initial condition
    sunindextype observed_data_cols = SM_COLUMNS_D(data);
    sunindextype data_cols = SM_COLUMNS_D(data);

    SUNMatrix observed_data = copy_matrix_remove_rows(data, create_array((long*){0}, 1));

    if (times_len != data_rows)
    {
        printf("ERROR: The number of rows in the observed data matrix must match the length of the times vector.\n");
        return;
    }

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

    // TODO: Ask if ignoring the first predicted params is what we want
    Results results = meigo(problem, options, times, data);
    N_Vector parameters_init = results.best; // Optimal parameters
    problem.parameters = parameters_init;
    // The original code solves the ode using this params but the result is not used again

    SUNMatrix resid_loo = SUNDenseMatrix(data_rows, observed_data_cols, get_sun_context());
    MatrixArray predicted_data_matrix = create_matrix_array(data_rows);
    SUNMatrix predicted_params_matrix = SUNDenseMatrix(data_rows, observed_data_cols, get_sun_context());

    // TODO: This can be done in parallel and the indices can be erroneous
    for (long i = 0; i < data_rows; ++i)
    {
        LongArray indices_to_remove = create_array((long[]) {i + 1}, 1);

        N_Vector texp = copy_vector_remove_indices(times, indices_to_remove);
        SUNMatrix yexp = copy_matrix_remove_rows(data, indices_to_remove);

        results = meigo(problem, options, texp, yexp);

        N_VDestroy_Serial(texp);
        SUNMatDestroy(yexp);

        N_Vector predicted_params = results.best; // TODO: Free this memory

        // Saving the predicted params obtained
        // This are
        set_matrix_row(predicted_params_matrix, predicted_params, i, 0, observed_data_cols);

        // Maybe this data is not needed once is proved that this way of predicting params works fine
        // Saving the ode solution data obtained with the predicted params
        SUNMatrix ode_solution = solve_ode(predicted_params, ode_model, time_constraints, tolerances);
        SUNMatrix predicted_data = copy_matrix_remove_columns(ode_solution, create_array((long[]) {1}, 1));

        SUNMatDestroy(ode_solution);

        for (int j = 0; j < observed_data_cols; ++j)
        {
            SM_ELEMENT_D(resid_loo, i, j) = abs(SM_ELEMENT_D(data, i, j) - SM_ELEMENT_D(predicted_data, i, j));
        }
        matrix_array_set_index(predicted_data_matrix, i,
                               predicted_data); // predicted_data_matrix takes ownership of predicted_data
    }

    // TODO: Output some of this data or all
    SUNMatrix predicted_data_median = matrix_array_get_median(predicted_data_matrix);
    N_Vector predicted_params_median = get_matrix_cols_median(predicted_params_matrix);

    double alp = 0.05;

    sunindextype m = observed_data_rows;
    sunindextype n = observed_data_cols;

    SUNMatrix q_low = SUNDenseMatrix(m, n, get_sun_context());
    SUNMatrix q_up = SUNDenseMatrix(m, n, get_sun_context());

    MatrixArray m_low = create_matrix_array(m);
    MatrixArray m_up = create_matrix_array(m);

    for (int i = 0; i < m; ++i)
    {
        matrix_array_set_index(m_low, i, SUNDenseMatrix(m, n, get_sun_context()));
        matrix_array_set_index(m_up, i, SUNDenseMatrix(m, n, get_sun_context()));
    }

    set_matrix_row(q_low, ode_model.initial_values, 0, 0, observed_data_cols);
    set_matrix_row(q_up, ode_model.initial_values, 0, 0, observed_data_cols);

    for (int i = 1; i < m + 1; ++i)
    {
        for (int j = 0; j < n; ++j)
        {
            for (int k = 0; k < (m - 1); ++k)
            {
                SM_ELEMENT_D(matrix_array_get_index(m_low, k), i, j) =
                        SM_ELEMENT_D(matrix_array_get_index(predicted_data_matrix, k + 1), i, j) -
                        SM_ELEMENT_D(resid_loo, k + 1, j);

                SM_ELEMENT_D(matrix_array_get_index(m_up, k), i, j) =
                        SM_ELEMENT_D(matrix_array_get_index(predicted_data_matrix, k + 1), i, j) +
                        SM_ELEMENT_D(resid_loo, k + 1, j);
            }

            SM_ELEMENT_D(q_low, i, j) = quantile(matrix_array_depth_vector_at(m_low, i, j), alp);
            SM_ELEMENT_D(q_up, i, j) = quantile(matrix_array_depth_vector_at(m_up, i, j), 1 - alp);
        }
    }

    destroy_matrix_array(predicted_data_matrix); // This frees the matrix array and all the matrices inside
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
    array.data = (SUNMatrix *) malloc(len * sizeof(SUNMatrix));
    return array;
}

void destroy_matrix_array(MatrixArray array)
{
    for (int i = 0; i < array.len; ++i)
    {
        SUNMatDestroy(array.data[i]);
    }

    free(array.data);
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
    double x = *(sunrealtype *)a;
    double y = *(sunrealtype *)b;

    if (x < y) return -1;
    if (x > y) return 1;
    return 0;
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

            medians[i * cols + j] =
                    max_z & 0b1 ? values[(max_z - 1) / 2] : (values[max_z / 2 - 1] + values[max_z / 2]) / 2;
        }
    }

    return medians_matrix;
}

N_Vector matrix_array_depth_vector_at(MatrixArray array, long i, long j)
{
    N_Vector vec = N_VNew_Serial(array.len, get_sun_context());

    for (int k = 0; k < array.len; ++k)
    {
        NV_Ith_S(vec, k) = SM_ELEMENT_D(matrix_array_get_index(array, k), i, j);
    }

    return vec;
}

N_Vector get_matrix_cols_median(SUNMatrix matrix)
{
    sunindextype rows = SM_ROWS_D(matrix);
    sunindextype cols = SM_COLUMNS_D(matrix);

    N_Vector medians_vector = N_VNew_Serial(cols, get_sun_context());
    sunrealtype *medians = NV_DATA_S(medians_vector);

    sunrealtype copied_col[rows];

    for (int j = 0; j < cols; ++j)
    {
        for (int i = 0; i < rows; ++i)
        {
            copied_col[i] = SM_DATA_D(matrix)[i * cols + j];
        }

        // Sorting the vector to obtain the median easily
        qsort(copied_col, rows, sizeof(copied_col[0]), compare_sunrealtype);

        medians[j] = rows & 0b1 ? copied_col[(rows - 1) / 2] : (copied_col[rows / 2 - 1] + copied_col[rows / 2]) / 2;
    }

    return medians_vector;
}
