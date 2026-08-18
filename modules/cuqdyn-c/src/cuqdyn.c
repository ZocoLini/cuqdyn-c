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
#include "sunmatrix/sunmatrix_dense.h"
#include "uq_bands.h"
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

CuqdynResult *create_cuqdyn_result(void)
{
    // Zeroed, so a field the caller does not set is NULL rather than garbage.
    return calloc(1, sizeof(CuqdynResult));
}
void destroy_cuqdyn_result(CuqdynResult *result)
{
    if (result == NULL)
    {
        return;
    }

    SUNMatDestroy(result->predicted_data_median);
    SUNMatDestroy(result->q_low);
    SUNMatDestroy(result->q_up);
    SUNMatDestroy(result->media_tot);
    SUNMatDestroy(result->cov_p);
    SUNMatDestroy(result->std_y);
    SUNMatDestroy(result->q_low_alt);
    SUNMatDestroy(result->q_up_alt);
    SUNMatDestroy(result->loo_params);
    SUNMatDestroy(result->resid_loo);

    N_VDestroy(result->predicted_params_median);
    N_VDestroy(result->times);
    N_VDestroy(result->parameters_init);

    free(result->observed_idx);
    free(result);
}

CuqdynResult *cuqdyn_algo(const char *data_file, const char *sacess_conf_file, const char *output_file)
{
    int rank;

#if defined(MPI2) || defined(MPI)
    int nproc;
    MPI_Comm_size(MPI_COMM_WORLD, &nproc);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
#else
    rank = 0;
#endif
    CuqdynConf *config = get_cuqdyn_conf(get_cuqdyn_context());

    CuqdynData data;
    if (read_data_file(data_file, &data) != 0)
    {
        fprintf(stderr, "Error reading data file: %s\n", data_file);
        exit(1);
    }

    N_Vector times = data.times;
    TransposedObservedData observed_data = data.observed_data;
    const int n_obs = data.n_obs;
    const long n_states = config->ode_expr.y_count;

    N_Vector scaled_times = N_VNew_Serial(NV_LENGTH_S(times), get_sundials_ctx());

    for (int i = 0; i < NV_LENGTH_S(times); ++i)
    {
        NV_Ith_S(scaled_times, i) = NV_Ith_S(times, i) * config->time_scaling;
    }

    const sunrealtype t0 = NV_Ith_S(scaled_times, 0);
    N_Vector initial_condition = NULL;

    if (config->y0.len == 0)
    {
        // Row 1 of the data file carries a finite value for every state,
        // hidden ones included, so it is the full initial condition.
        initial_condition = New_Serial(NV_LENGTH_S(data.initial_values));
        memcpy(NV_DATA_S(initial_condition), NV_DATA_S(data.initial_values),
               NV_LENGTH_S(data.initial_values) * sizeof(sunrealtype));
    }
    else
    {
        initial_condition = New_Serial(config->y0.len);
        memcpy(NV_DATA_S(initial_condition), config->y0.array, config->y0.len * sizeof(sunrealtype));
    }

    // observed_data is transposed: rows are measured states, columns time points
    const long n = SM_ROWS_D(observed_data);
    const long m = SM_COLUMNS_D(observed_data);

    SUNMatrix resid_loo = NULL;
    MatrixArray media_matrix = create_matrix_array(m - 1); // We will save transposed matrices inside the array
    SUNMatrix predicted_params_matrix = NULL;
    N_Vector initial_params = New_Serial(config->ode_expr.p_count);

    if (rank == 0)
    {
        resid_loo = NewDenseMatrix(m, n);
        // One row per leave-one-out refit. It used to have m rows with the
        // first left at zero, which dragged the median and would wreck the
        // covariance the hybrid method takes from this ensemble.
        predicted_params_matrix = NewDenseMatrix(m - 1, config->ode_expr.p_count);

        N_Vector texp = copy_vector_remove_indices(scaled_times, create_array((long[]) {}, 0));
        SUNMatrix yexp = copy_matrix_remove_rows(observed_data, create_array((long[]) {}, 0));

        N_Vector tmp_initial_condition = copy_vector_remove_indices(initial_condition, create_array((long[]) {}, 0));

        N_Vector predicted_params = execute_ess_solver(sacess_conf_file, output_file, texp, yexp, tmp_initial_condition,
                                                       NULL, data.observed_idx);

        // The solver dimension comes from the sacess config while p_count comes
        // from the cuqdyn config. A mismatch used to overflow initial_params.
        if (NV_LENGTH_S(predicted_params) != NV_LENGTH_S(initial_params))
        {
            fprintf(stderr,
                    "ERROR: the sacess config declares %ld decision variables but the cuqdyn config declares "
                    "p_count=%ld. They must match.\n",
                    NV_LENGTH_S(predicted_params), NV_LENGTH_S(initial_params));
            N_VDestroy(predicted_params);
            N_VDestroy(texp);
            SUNMatDestroy(yexp);
            N_VDestroy(tmp_initial_condition);
            N_VDestroy(initial_condition);
            N_VDestroy(scaled_times);
            N_VDestroy(initial_params);
            destroy_matrix_array(media_matrix);
            SUNMatDestroy(resid_loo);
            SUNMatDestroy(predicted_params_matrix);
            destroy_cuqdyn_data(&data);
            return NULL;
        }

        memcpy(NV_DATA_S(initial_params), NV_DATA_S(predicted_params),
               NV_LENGTH_S(predicted_params) * sizeof(sunrealtype));

        N_VDestroy(predicted_params);
    }

#ifdef MPI
    MPI_Bcast(NV_DATA_S(initial_params), NV_LENGTH_S(initial_params), MPI_DOUBLE, 0, MPI_COMM_WORLD);

    long iterations;
    long start_index;

    long min_iters_per_node = (long) ((m - 1) / (long) nproc);
    long remainder = (m - 1) % (long) nproc;

    // The leave-one-out points are split evenly, so the process count has to
    // divide m - 1. Every rank has to bail, not just the one that reports it:
    // if the others carried on they would block on sends nobody receives.
    if (remainder != 0)
    {
        if (rank == 0)
        {
            fprintf(stderr, "ERROR: %d processes do not divide m - 1 = %ld. Use a process count that divides it.\n",
                    nproc, m - 1);
        }

        N_VDestroy(initial_condition);
        N_VDestroy(scaled_times);
        N_VDestroy(initial_params);
        destroy_matrix_array(media_matrix);
        SUNMatDestroy(resid_loo);
        SUNMatDestroy(predicted_params_matrix);
        destroy_cuqdyn_data(&data);
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

        N_Vector texp = copy_vector_remove_indices(scaled_times, indices_to_remove);
        SUNMatrix yexp = copy_matrix_remove_columns(observed_data, indices_to_remove);

        N_Vector tmp_initial_condition = copy_vector_remove_indices(initial_condition, create_array((long[]) {}, 0));

        N_Vector predicted_params = execute_ess_solver(sacess_conf_file, output_file, texp, yexp, tmp_initial_condition,
                                                       initial_params, data.observed_idx);

        // Saving the ode solution data obtained with the predicted params
        TransposedStates predicted_obs_states = solve_ode(predicted_params, initial_condition, t0, scaled_times);

        for (int j = 0; j < n_obs; ++j)
        {
            const long state = data.observed_idx[j];
            const sunrealtype observed = SM_ELEMENT_D(observed_data, j, i);
            const sunrealtype predicted = SM_ELEMENT_D(predicted_obs_states, state, i);

            NV_Ith_S(residuals, j) = fabs(observed - predicted);
        }

#ifdef MPI
        long predicted_obs_states_len = SM_COLUMNS_D(predicted_obs_states) * SM_ROWS_D(predicted_obs_states);
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
            MPI_Send(SM_DATA_D(predicted_obs_states), predicted_obs_states_len, MPI_DOUBLE, 0, 2, MPI_COMM_WORLD);
            MPI_Send(NV_DATA_S(predicted_params), NV_LENGTH_S(predicted_params), MPI_DOUBLE, 0, 3, MPI_COMM_WORLD);
        }
        else
        {
#endif
            set_matrix_row(resid_loo, residuals, i, 0, NV_LENGTH_S(residuals));
            matrix_array_set_index(media_matrix, i - 1, predicted_obs_states);
            set_matrix_row(predicted_params_matrix, predicted_params, i - 1, 0, NV_LENGTH_S(predicted_params));
#ifdef MPI
            // Receiving
            long slaved_index;
            for (int slave = 1; slave < nproc; ++slave)
            {
                MPI_Recv(&slaved_index, 1, MPI_LONG, slave, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);

                // Receriving the residuals of other processes
                MPI_Recv(NV_DATA_S(residuals), NV_LENGTH_S(residuals), MPI_DOUBLE, slave, 1, MPI_COMM_WORLD,
                         MPI_STATUS_IGNORE);
                set_matrix_row(resid_loo, residuals, slaved_index, 0, NV_LENGTH_S(residuals));

                // Receiving the predicted data matrix
                MPI_Recv(SM_DATA_D(predicted_obs_states), predicted_obs_states_len, MPI_DOUBLE, slave, 2,
                         MPI_COMM_WORLD, MPI_STATUS_IGNORE);
                matrix_array_set_index(media_matrix, slaved_index - 1, predicted_obs_states);

                // Receiving the predicted params
                MPI_Recv(NV_DATA_S(predicted_params), NV_LENGTH_S(predicted_params), MPI_DOUBLE, slave, 3,
                         MPI_COMM_WORLD, MPI_STATUS_IGNORE);
                set_matrix_row(predicted_params_matrix, predicted_params, slaved_index - 1, 0,
                               NV_LENGTH_S(predicted_params));
            }
        }
#endif
        if (rank == 0)
        {
            fprintf(stdout, "Iteration %ld of %ld done\n", i - start_index + 1, end_index - start_index);
        }

        N_VDestroy(predicted_params);
        SUNMatDestroy(predicted_obs_states);
    }

    N_VDestroy(residuals);

#ifdef MPI
    printf("%ld iterations of rank %d finalized\n", iterations, rank);
#endif

    if (rank != 0)
    {
        N_VDestroy(initial_condition);
        N_VDestroy(scaled_times);
        destroy_cuqdyn_data(&data);
        return NULL;
    }

    // media_matrix is transposed so predicted data median is also transposed
    TransposedStates predicted_data_median = matrix_array_get_median(media_matrix);

    N_Vector predicted_params_median = get_matrix_cols_median(predicted_params_matrix);
    for (int i = 0; i < NV_LENGTH_S(predicted_params_median); ++i) // Parameters are also affected by the time scaling
    {
        NV_Ith_S(predicted_params_median, i) = NV_Ith_S(predicted_params_median, i) * config->time_scaling;
    }

    const double alp = config->alp;

    // Bands cover every state, not just the measured ones.
    SUNMatrix q_low = NewDenseMatrix(m, n_states);
    SUNMatrix q_up = NewDenseMatrix(m, n_states);

    for (long k = 0; k < n_states; ++k)
    {
        SM_ELEMENT_D(q_low, 0, k) = NV_Ith_S(initial_condition, k);
        SM_ELEMENT_D(q_up, 0, k) = NV_Ith_S(initial_condition, k);
    }

    conformal_bands(media_matrix, resid_loo, data.observed_idx, n_obs, alp, q_low, q_up);

    /* ---- Delta-method bands for the hidden states ---------------------- */
    SUNMatrix cov_p = NULL;
    SUNMatrix std_y = NULL;
    SUNMatrix q_low_alt = NULL;
    SUNMatrix q_up_alt = NULL;
    TransposedStates media_tot = solve_ode(initial_params, initial_condition, t0, scaled_times);

    if (media_tot == NULL)
    {
        fprintf(stderr, "ERROR: could not solve the ODE at the best-fit parameters\n");
    }
    else if (delta_method_bands(initial_params, initial_condition, t0, scaled_times, media_tot, observed_data,
                                data.observed_idx, n_obs, predicted_params_matrix, q_low, q_up, &cov_p, &std_y,
                                &q_low_alt, &q_up_alt) != 0)
    {
        fprintf(stderr, "ERROR: could not propagate the parameter covariance\n");
    }

    destroy_matrix_array(media_matrix);
    N_VDestroy(initial_condition);

    CuqdynResult *result = create_cuqdyn_result();

    result->predicted_data_median = predicted_data_median;
    result->predicted_params_median = predicted_params_median;
    result->q_low = q_low;
    result->q_up = q_up;
    result->q_low_alt = q_low_alt;
    result->q_up_alt = q_up_alt;
    result->media_tot = media_tot;
    result->parameters_init = initial_params;
    result->cov_p = cov_p;
    result->std_y = std_y;
    result->loo_params = predicted_params_matrix;
    result->resid_loo = resid_loo;
    result->n_obs = n_obs;
    result->n_states = n_states;

    result->times = New_Serial(NV_LENGTH_S(times));
    memcpy(NV_DATA_S(result->times), NV_DATA_S(times), NV_LENGTH_S(times) * sizeof(sunrealtype));

    result->observed_idx = malloc(n_obs * sizeof(int));
    memcpy(result->observed_idx, data.observed_idx, n_obs * sizeof(int));

    N_VDestroy(scaled_times);
    destroy_cuqdyn_data(&data);

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
        SUNMatDestroy(array.data[i]);
    }

    free((void *) array.data);
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
