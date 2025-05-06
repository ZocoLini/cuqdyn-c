#include "cuqdyn.h"

#include <data_reader.h>
#include <ess_solver.h>
#include <functions/lotka_volterra.h>
#include <math.h>
#include <nvector_old/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sundials_old/sundials_nvector.h>

#include "matlab.h"
#include "ode_solver.h"

FunctionType create_function_type(int function_type)
{
    FunctionType out;

    switch (function_type)
    {
        case 0:
            out = LOTKA_VOLTERRA;
            break;
        case 1:
            out = ALPHA_PINENE;
            break;
        case 2:
            out = LOGISTIC;
            break;
        case 3:
            out = CUSTOM;
            break;
        default:
            out = NONE;
    }

    return out;
}

OdeModelFun obtain_function_type_f(const FunctionType function_type)
{
    OdeModelFun out = NULL;

    switch (function_type)
    {
        case LOTKA_VOLTERRA:
            out = lotka_volterra_f;
            break;
        case ALPHA_PINENE:
        case LOGISTIC:
        case CUSTOM:
            fprintf(stderr, "Not yet implemented");
            exit(1);
            break;
        default:
            fprintf(stderr, "Unsupported function type");
            exit(1);
    }

    return out;
}

ObjFunc obtain_function_type_obj_f(const FunctionType function_type)
{
    ObjFunc out = NULL;

    switch (function_type)
    {
        case LOTKA_VOLTERRA:
            out = lotka_volterra_obj_f;
            break;
        case ALPHA_PINENE:
        case LOGISTIC:
        case CUSTOM:
            fprintf(stderr, "Not yet implemented");
            exit(1);
            break;
        default:
            fprintf(stderr, "Unsupported function type");
            exit(1);
    }

    return out;
}

CuqdynResult *create_cuqdyn_result(DlsMat predicted_data_median, N_Vector predicted_params_median, DlsMat q_low,
                                   DlsMat q_up, N_Vector times)
{
    CuqdynResult *cuqdyn_result = malloc(sizeof(CuqdynResult));
    cuqdyn_result->predicted_data_median = predicted_data_median;
    cuqdyn_result->predicted_params_median = predicted_params_median;
    cuqdyn_result->q_low = q_low;
    cuqdyn_result->q_up = q_up;
    cuqdyn_result->times = times;
    return cuqdyn_result;
}
void destroy_cuqdyn_result(CuqdynResult *result)
{
    SUNMatDestroy(result->predicted_data_median);
    SUNMatDestroy(result->q_low);
    SUNMatDestroy(result->q_up);

    N_VDestroy(result->predicted_params_median);
    N_VDestroy(result->times);
    free(result);
}

CuqdynResult *cuqdyn_algo(FunctionType function_type, const char *data_file, const char *sacess_conf_file,
                          const char *output_file)
{
    N_Vector times = NULL;
    DlsMat observed_data = NULL;

    if (read_data_file(data_file, &times, &observed_data) != 0)
    {
        fprintf(stderr, "Error reading data file: %s\n", data_file);
        exit(1);
    }

    const realtype t0 = NV_Ith_S(times, 0);
    N_Vector initial_values = copy_matrix_row(observed_data, 0, 0, SM_COLUMNS_D(observed_data));

    const long m = SM_ROWS_D(observed_data);
    const long n = SM_COLUMNS_D(observed_data);

    const OdeModelFun ode_model_fun = obtain_function_type_f(function_type);
    const ObjFunc obj_func = obtain_function_type_obj_f(function_type);

    const ODEModel ode_model = create_ode_model(2, ode_model_fun, initial_values, t0, times);

    /*
     * problem.f='prob_mod_lv';
     * problem.x_L=0.001*ones(1,4); % Lower bounds of the variables
     * problem.x_U=ones(1,4); % Upper bounds of the variables
     * problem.x_0=[0.3, 0.3, 0.3, 0.3]; % Initial points
     * opts.maxeval=3e3; % Maximum number of function evaluations (default 1000)
     * opts.log_var=[1:4]; % Indexes of the variables which will be analyzed using a logarithmic distribution instead of
     * an uniform one
     * opts.local.solver='nl2sol'; % Local solver to perform the local search
     * opts.inter_save=1; % Saves results of intermediate iterations in eSS_report.mat
     */

    DlsMat resid_loo = SUNDenseMatrix(m, n, get_sun_context());
    MatrixArray media_matrix = create_matrix_array(m - 1);
    DlsMat predicted_params_matrix = NULL;

    // The original code solves the ode using this params but the result is not used again
    // but we found a usage, using the result to see the number of params
    {
        LongArray indices_to_remove = create_array((long[]) {}, 0);
        N_Vector texp = copy_vector_remove_indices(times, indices_to_remove);
        DlsMat yexp = copy_matrix_remove_rows(observed_data, indices_to_remove);
        N_Vector init_vals = N_VNew_Serial(NV_LENGTH_S(initial_values), get_sun_context());
        memcpy(N_VGetArrayPointer(init_vals), N_VGetArrayPointer(initial_values), NV_LENGTH_S(initial_values) * sizeof(realtype));
        N_Vector init_pred_params = execute_ess_solver(sacess_conf_file, output_file, obj_func, texp, yexp, init_vals);
        predicted_params_matrix = SUNDenseMatrix(m, NV_LENGTH_S(init_pred_params), get_sun_context());
    }

    // TODO: This can be done in parallel
    for (long i = 1; i < m; ++i)
    {
        LongArray indices_to_remove = create_array((long[]) {i + 1}, 1);

        N_Vector texp = copy_vector_remove_indices(times, indices_to_remove);
        DlsMat yexp = copy_matrix_remove_rows(observed_data, indices_to_remove);

        N_Vector init_vals = N_VNew_Serial(NV_LENGTH_S(initial_values), get_sun_context());
        memcpy(N_VGetArrayPointer(init_vals), N_VGetArrayPointer(initial_values), NV_LENGTH_S(initial_values) * sizeof(realtype));
        N_Vector predicted_params = execute_ess_solver(sacess_conf_file, output_file, obj_func, texp, yexp, init_vals);

        // Saving the predicted params obtained
        set_matrix_row(predicted_params_matrix, predicted_params, i, 0, NV_LENGTH_S(predicted_params));

        // Saving the ode solution data obtained with the predicted params
        DlsMat ode_solution = solve_ode(predicted_params, ode_model);
        DlsMat predicted_data = copy_matrix_remove_columns(ode_solution, create_array((long[]) {1L}, 1));

        SUNMatDestroy(ode_solution);
        N_VDestroy(predicted_params);

        for (int j = 0; j < n; ++j)
        {
            realtype observed = SM_ELEMENT_D(observed_data, i, j);
            realtype predicted = SM_ELEMENT_D(predicted_data, i, j);

            SM_ELEMENT_D(resid_loo, i, j) = fabs(observed - predicted);
        }
        matrix_array_set_index(media_matrix, i - 1, predicted_data);
    }

    DlsMat predicted_data_median = matrix_array_get_median(media_matrix);
    N_Vector predicted_params_median = get_matrix_cols_median(predicted_params_matrix);

    double alp = 0.05;

    DlsMat q_low = SUNDenseMatrix(m, n, get_sun_context());
    DlsMat q_up = SUNDenseMatrix(m, n, get_sun_context());

    for (int i = 0; i < n; ++i)
    {
        SM_ELEMENT_D(q_low, 0, i) = NV_Ith_S(initial_values, i);
        SM_ELEMENT_D(q_up, 0, i) = NV_Ith_S(initial_values, i);
    }

    MatrixArray m_low = create_matrix_array(m - 1);
    MatrixArray m_up = create_matrix_array(m - 1);

    for (int i = 0; i < m - 1; ++i)
    {
        matrix_array_set_index(m_low, i, SUNDenseMatrix(m, n, get_sun_context()));
        matrix_array_set_index(m_up, i, SUNDenseMatrix(m, n, get_sun_context()));
    }

    for (int j = 0; j < n; ++j)
    {
        for (int i = 1; i < m; ++i)
        {
            for (int k = 1; k < m; ++k)
            {
                SM_ELEMENT_D(matrix_array_get_index(m_low, k - 1), i, j) =
                        SM_ELEMENT_D(matrix_array_get_index(media_matrix, k - 1), i, j) -
                        SM_ELEMENT_D(resid_loo, k, j);

                SM_ELEMENT_D(matrix_array_get_index(m_up, k - 1), i, j) =
                        SM_ELEMENT_D(matrix_array_get_index(media_matrix, k - 1), i, j) +
                        SM_ELEMENT_D(resid_loo, k, j);
            }

            SM_ELEMENT_D(q_low, i, j) = quantile(matrix_array_depth_vector_at(m_low, i, j), alp);
            SM_ELEMENT_D(q_up, i, j) = quantile(matrix_array_depth_vector_at(m_up, i, j), 1 - alp);
        }
    }

    destroy_matrix_array(m_low);
    destroy_matrix_array(m_up);
    destroy_matrix_array(media_matrix);
    N_VDestroy(initial_values);
    SUNMatDestroy(observed_data);

    CuqdynResult *result = create_cuqdyn_result(
        predicted_data_median,
        predicted_params_median,
        q_low,
        q_up,
        times
        );

    return result;
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
    array.data = (DlsMat *) malloc(len * sizeof(DlsMat));
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

DlsMat matrix_array_get_index(MatrixArray array, long i)
{
    if (i < 0 || i >= array.len)
    {
        printf("ERROR: Index out of bounds in function matrix_array_get_index()\n");
        return NULL;
    }

    return array.data[i];
}

void matrix_array_set_index(MatrixArray array, long i, DlsMat matrix)
{
    if (i < 0 || i >= array.len)
    {
        printf("ERROR: Index out of bounds in function matrix_array_get_index()\n");
        return;
    }

    array.data[i] = matrix;
}

int compare_realtype(const void *a, const void *b)
{
    double x = *(realtype *) a;
    double y = *(realtype *) b;

    if (x < y)
        return -1;
    if (x > y)
        return 1;
    return 0;
}

DlsMat matrix_array_get_median(MatrixArray matrix_array)
{
    DlsMat first_matrix = matrix_array_get_index(matrix_array, 0);
    long rows = SM_ROWS_D(first_matrix);
    long cols = SM_COLUMNS_D(first_matrix);

    long max_z = matrix_array.len;

    DlsMat medians_matrix = SUNDenseMatrix(rows, cols, get_sun_context());
    realtype *medians = medians_matrix->data;

    realtype values[max_z];

    for (int i = 0; i < rows; ++i)
    {
        for (int j = 0; j < cols; ++j)
        {
            for (int z = 0; z < max_z; ++z)
            {
                DlsMat actual_matrix = matrix_array_get_index(matrix_array, z);
                values[z] = SM_ELEMENT_D(actual_matrix, i, j);
            }

            // Sorting the vector to obtain the median easily
            qsort(values, max_z, sizeof(values[0]), compare_realtype);

            SM_ELEMENT_D(medians_matrix, i, j) = max_z & 0b1 ? values[(max_z - 1) / 2] : (values[max_z / 2 - 1] + values[max_z / 2]) / 2;
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

N_Vector get_matrix_cols_median(DlsMat matrix)
{
    long rows = SM_ROWS_D(matrix);
    long cols = SM_COLUMNS_D(matrix);

    N_Vector medians_vector = N_VNew_Serial(cols, get_sun_context());
    realtype *medians = NV_DATA_S(medians_vector);

    realtype copied_col[rows];

    for (int j = 0; j < cols; ++j)
    {
        for (int i = 0; i < rows; ++i)
        {
            copied_col[i] = SM_ELEMENT_D(matrix, i, j);
        }

        // Sorting the vector to obtain the median easily
        qsort(copied_col, rows, sizeof(copied_col[0]), compare_realtype);

        medians[j] = rows & 0b1 ? copied_col[(rows - 1) / 2] : (copied_col[rows / 2 - 1] + copied_col[rows / 2]) / 2;
    }

    return medians_vector;
}
