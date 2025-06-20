#include "cuqdyn.h"

#include <data_reader.h>
#include <ess_solver.h>
#include <math.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "matlab.h"
#include "ode_solver.h"
#ifdef MPI
#include <mpi.h>
#endif

SUNContext get_sundials_ctx()
{
    static SUNContext ctx = NULL;

    if (ctx == NULL)
    {
        SUNContext_Create(SUN_COMM_NULL, &ctx);
    }

    return ctx;
}

CuqdynResult *create_cuqdyn_result(SUNMatrix predicted_data_median, N_Vector predicted_params_median, SUNMatrix q_low,
                                   SUNMatrix q_up, N_Vector times)
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

CuqdynResult *cuqdyn_algo(const char *data_file, const char *sacess_conf_file, const char *output_file)
{
    int nproc;
    int rank;

#if defined(MPI2) || defined(MPI)
    MPI_Comm_size(MPI_COMM_WORLD, &nproc);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
#else
    nproc = 1;
    rank = 0;
#endif
    CuqdynConf *config = get_cuqdyn_conf();

    N_Vector times = NULL;
    SUNMatrix observed_data = NULL;

    if (read_data_file(data_file, &times, &observed_data) != 0)
    {
        fprintf(stderr, "Error reading data file: %s\n", data_file);
        exit(1);
    }

    const sunrealtype t0 = NV_Ith_S(times, 0);
    N_Vector initial_condition = copy_matrix_row(observed_data, 0, 0, SM_COLUMNS_D(observed_data));

    const long m = SM_ROWS_D(observed_data);
    const long n = SM_COLUMNS_D(observed_data);

    SUNMatrix resid_loo = NULL;
    MatrixArray media_matrix = create_matrix_array(m - 1);
    SUNMatrix predicted_params_matrix = NULL;
    N_Vector initial_params = New_Serial(get_cuqdyn_conf()->ode_expr.p_count);

    if (rank == 0)
    {
        resid_loo = NewDenseMatrix(m, n);
        predicted_params_matrix = NewDenseMatrix(m, config->ode_expr.p_count);

        N_Vector texp = copy_vector_remove_indices(times, create_array((long[]) {}, 0));
        SUNMatrix yexp = copy_matrix_remove_rows(observed_data, create_array((long[]) {}, 0));

        N_Vector tmp_initial_condition = copy_vector_remove_indices(initial_condition, create_array((long[]) {}, 0));

        N_Vector predicted_params =
            execute_ess_solver(sacess_conf_file, output_file, texp, yexp, tmp_initial_condition, NULL);

        memcpy(NV_DATA_S(initial_params), NV_DATA_S(predicted_params), NV_LENGTH_S(predicted_params) * sizeof(sunrealtype));
        N_VDestroy(predicted_params);
    }

#ifdef MPI
    MPI_Bcast(NV_DATA_S(initial_params), NV_LENGTH_S(initial_params), MPI_DOUBLE, 0, MPI_COMM_WORLD);

    long iterations;
    long start_index;

    long min_iters_per_node = (long) ((m - 1) / (long) nproc);
    long remainder = (m - 1) % (long) nproc;

    // Old and optimal version. It accepts any number of processes but causes deadlock when the number of processes
    // is not a divisor of m - 1 due to the use of MPI_Barrier(MPI_COMM_WORLD);
    // if (remainder > rank)
    // {
    //     iterations = min_iters_per_node;
    //     start_index = rank * iterations + 1;
    // }
    // else
    // {
    //     iterations = min_iters_per_node;
    //     start_index = (remainder * (min_iters_per_node + 1)) + ((rank - remainder) * min_iters_per_node) + 1;
    // }

    // New version. Only iterates over every row if the number of processes is a divisor of m - 1
    if (remainder != 0 && rank == 0)
    {
        fprintf(stderr, "Number of processes is not a divisor of m - 1. Please use a number of processes that is a "
                        "divisor of m - 1\n");
        return NULL;
    }
    iterations = min_iters_per_node;
    start_index = rank * iterations + 1;

#else
    long iterations = m - 1;
    long start_index = 1;
#endif

    N_Vector residuals = New_Serial(n);
    const long end_index = iterations + start_index;

    for (long i = start_index; i < end_index; ++i)
    {
        LongArray indices_to_remove = create_array((long[]) {i + 1}, 1);

        N_Vector texp = copy_vector_remove_indices(times, indices_to_remove);
        SUNMatrix yexp = copy_matrix_remove_rows(observed_data, indices_to_remove);

        N_Vector tmp_initial_condition = copy_vector_remove_indices(initial_condition, create_array((long[]) {}, 0));

        N_Vector predicted_params =
                execute_ess_solver(sacess_conf_file, output_file, texp, yexp, tmp_initial_condition, initial_params);

        // Saving the ode solution data obtained with the predicted params
        SUNMatrix ode_solution = solve_ode(predicted_params, initial_condition, t0, times);
        SUNMatrix predicted_data = copy_matrix_remove_columns(ode_solution, create_array((long[]) {1L}, 1));
        SUNMatDestroy(ode_solution);

        for (int j = 0; j < n; ++j)
        {
            sunrealtype observed = SM_ELEMENT_D(observed_data, i, j);
            sunrealtype predicted = SM_ELEMENT_D(predicted_data, i, j);

            NV_Ith_S(residuals, j) = fabs(observed - predicted);
        }

#ifdef MPI
        long predicted_data_len = SM_COLUMNS_D(predicted_data) * SM_ROWS_D(predicted_data);
        if (rank != 0)
        {
            // Sending
            // Tag 0 is used to send the acutal i (row / time)
            // Tag 1 is used to send the residuals vector
            // Tag 2 is used to send the predicted data matrix
            // Tag 3 is used to send the predicted params vector
            // We also need to send the actual i to the master process
            MPI_Send(&i, 1, MPI_LONG, 0, 0, MPI_COMM_WORLD);
            MPI_Send(NV_DATA_S(residuals), NV_LENGTH_S(residuals), MPI_DOUBLE, 0, 1, MPI_COMM_WORLD);
            MPI_Send(SM_DATA_D(predicted_data), predicted_data_len, MPI_DOUBLE, 0, 2, MPI_COMM_WORLD);
            MPI_Send(NV_DATA_S(predicted_params), NV_LENGTH_S(predicted_params), MPI_DOUBLE, 0, 3, MPI_COMM_WORLD);
        }
        else
        {
#endif
            set_matrix_row(resid_loo, residuals, i, 0, NV_LENGTH_S(residuals));
            matrix_array_set_index(media_matrix, i - 1, predicted_data);
            set_matrix_row(predicted_params_matrix, predicted_params, i, 0, NV_LENGTH_S(predicted_params));
#ifdef MPI
            // Receiving
            long slaved_index;
            for (int slave = 1; slave < nproc; ++slave)
            {
                MPI_Recv(&slaved_index, 1, MPI_LONG, slave, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);

                // Receriving the residuals of other processes
                MPI_Recv(NV_DATA_S(residuals), NV_LENGTH_S(residuals), MPI_DOUBLE, slave, 1, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
                set_matrix_row(resid_loo, residuals, slaved_index, 0, NV_LENGTH_S(residuals));

                // Receiving the predicted data matrix
                MPI_Recv(SM_DATA_D(predicted_data), predicted_data_len, MPI_DOUBLE, slave, 2, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
                matrix_array_set_index(media_matrix, slaved_index - 1, predicted_data);

                // Receiving the predicted params
                MPI_Recv(NV_DATA_S(predicted_params), NV_LENGTH_S(predicted_params), MPI_DOUBLE, slave, 3, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
                set_matrix_row(predicted_params_matrix, predicted_params, slaved_index, 0, NV_LENGTH_S(predicted_params));
            }
        }
#endif
        if (rank == 0)
        {
            fprintf(stdout, "Iteration %ld of %ld done\n", i - start_index + 1, end_index - start_index);
        }

        N_VDestroy(predicted_params);
        SUNMatDestroy(predicted_data);
    }

N_VDestroy(residuals);

#ifdef MPI
    printf("%ld iterations of rank %d finalized\n", iterations, rank);
#endif

    if (rank != 0)
    {
        N_VDestroy(initial_condition);
        SUNMatDestroy(observed_data);
        return NULL;
    }

    SUNMatrix predicted_data_median = matrix_array_get_median(media_matrix);
    N_Vector predicted_params_median = get_matrix_cols_median(predicted_params_matrix);

    double alp = 0.05;

    SUNMatrix q_low = NewDenseMatrix(m, n);
    SUNMatrix q_up = NewDenseMatrix(m, n);

    for (int i = 0; i < n; ++i)
    {
        SM_ELEMENT_D(q_low, 0, i) = NV_Ith_S(initial_condition, i);
        SM_ELEMENT_D(q_up, 0, i) = NV_Ith_S(initial_condition, i);
    }

    MatrixArray m_low = create_matrix_array(m - 1);
    MatrixArray m_up = create_matrix_array(m - 1);

    for (int i = 0; i < m - 1; ++i)
    {
        matrix_array_set_index(m_low, i, NewDenseMatrix(m, n));
        matrix_array_set_index(m_up, i, NewDenseMatrix(m, n));
    }

    for (int j = 0; j < n; ++j)
    {
        for (int i = 1; i < m; ++i)
        {
            for (int k = 1; k < m; ++k)
            {
                SM_ELEMENT_D(matrix_array_get_index(m_low, k - 1), i, j) =
                        SM_ELEMENT_D(matrix_array_get_index(media_matrix, k - 1), i, j) - SM_ELEMENT_D(resid_loo, k, j);

                SM_ELEMENT_D(matrix_array_get_index(m_up, k - 1), i, j) =
                        SM_ELEMENT_D(matrix_array_get_index(media_matrix, k - 1), i, j) + SM_ELEMENT_D(resid_loo, k, j);
            }

            SM_ELEMENT_D(q_low, i, j) = quantile(matrix_array_depth_vector_at(m_low, i, j), alp);
            SM_ELEMENT_D(q_up, i, j) = quantile(matrix_array_depth_vector_at(m_up, i, j), 1 - alp);
        }
    }

    destroy_matrix_array(m_low);
    destroy_matrix_array(m_up);
    destroy_matrix_array(media_matrix);
    N_VDestroy(initial_condition);
    SUNMatDestroy(observed_data);
    SUNMatDestroy(resid_loo);
    SUNMatDestroy(predicted_params_matrix);

    CuqdynResult *result = create_cuqdyn_result(predicted_data_median, predicted_params_median, q_low, q_up, times);

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
    array.data = (SUNMatrix *) calloc(len, sizeof(SUNMatrix));
    return array;
}

void destroy_matrix_array(MatrixArray array)
{
    if (array.data == NULL)
    {
        fprintf(stderr, "ERROR: Matrix array data is NULL in function destroy_matrix_array()\n");
        return;
    }

    for (int i = 0; i < array.len; ++i)
    {
        if (array.data[i] != NULL)
        {
            SUNMatDestroy(array.data[i]);
        }
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

    if (array.data == NULL)
    {
        fprintf(stderr, "ERROR: Matrix array data is NULL in function matrix_array_get_index()\n");
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

    long rows = SM_ROWS_D(matrix);
    long cols = SM_COLUMNS_D(matrix);

    if (array.data == NULL)
    {
        fprintf(stderr, "ERROR: Matrix array data is NULL in function matrix_array_get_index()\n");
        return;
    }

    array.data[i] = NewDenseMatrix(rows, cols);

    memcpy(SM_DATA_D(array.data[i]), SM_DATA_D(matrix), rows * cols * sizeof(sunrealtype));
}

int compare_sunrealtype(const void *a, const void *b)
{
    double x = *(sunrealtype *) a;
    double y = *(sunrealtype *) b;

    if (x < y)
        return -1;
    if (x > y)
        return 1;
    return 0;
}

SUNMatrix matrix_array_get_median(MatrixArray matrix_array)
{
    SUNMatrix first_matrix = matrix_array_get_index(matrix_array, 0);
    long rows = SM_ROWS_D(first_matrix);
    long cols = SM_COLUMNS_D(first_matrix);

    long max_z = matrix_array.len;

    SUNMatrix medians_matrix = NewDenseMatrix(rows, cols);
    sunrealtype *medians = SM_DATA_D(medians_matrix);

    sunrealtype values[max_z];

    for (int i = 0; i < rows; ++i)
    {
        for (int j = 0; j < cols; ++j)
        {
            for (int z = 0; z < max_z; ++z)
            {
                SUNMatrix actual_matrix = matrix_array_get_index(matrix_array, z);
                values[z] = SM_ELEMENT_D(actual_matrix, i, j);
            }

            // Sorting the vector to obtain the median easily
            qsort(values, max_z, sizeof(values[0]), compare_sunrealtype);

            SM_ELEMENT_D(medians_matrix, i, j) =
                    max_z & 0b1 ? values[(max_z - 1) / 2] : (values[max_z / 2 - 1] + values[max_z / 2]) / 2;
        }
    }

    return medians_matrix;
}

N_Vector matrix_array_depth_vector_at(MatrixArray array, long i, long j)
{
    N_Vector vec = New_Serial(array.len);

    for (int k = 0; k < array.len; ++k)
    {
        NV_Ith_S(vec, k) = SM_ELEMENT_D(matrix_array_get_index(array, k), i, j);
    }

    return vec;
}

N_Vector get_matrix_cols_median(SUNMatrix matrix)
{
    long rows = SM_ROWS_D(matrix);
    long cols = SM_COLUMNS_D(matrix);

    N_Vector medians_vector = New_Serial(cols);
    sunrealtype *medians = NV_DATA_S(medians_vector);

    sunrealtype copied_col[rows];

    for (int j = 0; j < cols; ++j)
    {
        for (int i = 0; i < rows; ++i)
        {
            copied_col[i] = SM_ELEMENT_D(matrix, i, j);
        }

        // Sorting the vector to obtain the median easily
        qsort(copied_col, rows, sizeof(copied_col[0]), compare_sunrealtype);

        medians[j] = rows & 0b1 ? copied_col[(rows - 1) / 2] : (copied_col[rows / 2 - 1] + copied_col[rows / 2]) / 2;
    }

    return medians_vector;
}
