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
#include <method_module/structure_paralleltestbed.h>
#include <mpi.h>
#endif

#ifdef MPI
/// Size of part `part` when `total` is split into `parts` as evenly as possible,
/// the first parts taking the remainder.
static long share_size(const long total, const long parts, const long part)
{
    return total / parts + (part < total % parts ? 1 : 0);
}

/// Where part `part` of that split starts, 0-based.
static long share_start(const long total, const long parts, const long part)
{
    const long remainder = total % parts;

    return part * (total / parts) + (part < remainder ? part : remainder);
}

/*
 * How the ranks share the leave-one-out refits. The ranks are split into
 * min(nproc, points) groups of contiguous ranks, as evenly as possible. With no
 * more ranks than refits every group is a single rank; the ranks left over join
 * the groups, and sacess runs each refit in parallel over its group.
 *
 * Every rank computes the same layout from nproc and points, so it needs no
 * communication, and each rank knows before the loop whether it leads a group
 * (and so needs the buffers for the results) or only works inside sacess. Which
 * refits a group runs is decided as the loop goes, see next_refit.
 */
typedef struct
{
    long n_groups;
    long group;
    /// World rank of the first rank of the group, the one that reports to rank 0.
    int leader;
} LoopLayout;

static LoopLayout loop_layout(const long points, const int nproc, const int rank)
{
    LoopLayout layout;

    layout.n_groups = points < nproc ? points : nproc;
    if (layout.n_groups < 1)
    {
        layout.n_groups = 1;
    }

    layout.group = 0;
    while (rank >= share_start(nproc, layout.n_groups, layout.group) + share_size(nproc, layout.n_groups, layout.group))
    {
        ++layout.group;
    }

    layout.leader = (int) share_start(nproc, layout.n_groups, layout.group);

    return layout;
}
#endif

/*
 * The results of the refits a group leader ran, packed one record after another
 * as [index, residuals, predicted states, params], so they reach rank 0 in a
 * single message once the loop is over.
 */
typedef struct
{
    long n_residuals;
    long states_rows;
    long states_cols;
    long n_params;
    long count;
    long capacity;
    double *data;
} RefitRecords;

static long refit_record_len(const RefitRecords *records)
{
    return 1 + records->n_residuals + records->states_rows * records->states_cols + records->n_params;
}

static void append_refit_record(RefitRecords *records, const long index, N_Vector residuals, SUNMatrix states,
                                N_Vector params)
{
    const long len = refit_record_len(records);

    if (records->count == records->capacity)
    {
        const long capacity = records->capacity == 0 ? 4 : 2 * records->capacity;
        double *grown = realloc(records->data, capacity * len * sizeof(double));
        if (grown == NULL)
        {
            fprintf(stderr, "ERROR: out of memory storing the leave-one-out results\n");
            exit(1);
        }
        records->data = grown;
        records->capacity = capacity;
    }

    double *record = records->data + records->count * len;
    const long states_len = records->states_rows * records->states_cols;

    record[0] = (double) index;
    memcpy(record + 1, NV_DATA_S(residuals), records->n_residuals * sizeof(double));
    memcpy(record + 1 + records->n_residuals, SM_DATA_D(states), states_len * sizeof(double));
    memcpy(record + 1 + records->n_residuals + states_len, NV_DATA_S(params), records->n_params * sizeof(double));

    ++records->count;
}

/// Writes `count` packed records into rank 0's result matrices.
static void store_refit_records(const RefitRecords *layout, const double *data, const long count, SUNMatrix resid_loo,
                                MatrixArray media_matrix, SUNMatrix predicted_params_matrix)
{
    const long len = refit_record_len(layout);
    const long states_len = layout->states_rows * layout->states_cols;

    N_Vector residuals = New_Serial(layout->n_residuals);
    SUNMatrix states = NewDenseMatrix(layout->states_rows, layout->states_cols);
    N_Vector params = New_Serial(layout->n_params);

    for (long k = 0; k < count; ++k)
    {
        const double *record = data + k * len;
        const long i = (long) record[0];

        memcpy(NV_DATA_S(residuals), record + 1, layout->n_residuals * sizeof(double));
        memcpy(SM_DATA_D(states), record + 1 + layout->n_residuals, states_len * sizeof(double));
        memcpy(NV_DATA_S(params), record + 1 + layout->n_residuals + states_len, layout->n_params * sizeof(double));

        set_matrix_row(resid_loo, residuals, i, 0, layout->n_residuals);
        matrix_array_set_index(media_matrix, i - 1, states);
        set_matrix_row(predicted_params_matrix, params, i - 1, 0, layout->n_params);
    }

    N_VDestroy(residuals);
    SUNMatDestroy(states);
    N_VDestroy(params);
}

#ifdef MPI
/*
 * The next refit for the calling rank's group, 1-based. The leader takes it
 * from a counter on rank 0 and passes it to the rest of its group, so a group
 * that finishes early goes on with the refits still pending instead of waiting
 * for the others. An index past the last refit means the loop is over.
 */
static long next_refit(const int is_leader, MPI_Win counter_win, MPI_Comm group_comm)
{
    long taken = 0;

    if (is_leader)
    {
        const long one = 1;

        MPI_Win_lock(MPI_LOCK_SHARED, 0, 0, counter_win);
        MPI_Fetch_and_op(&one, &taken, MPI_LONG, 0, 0, MPI_SUM, counter_win);
        MPI_Win_unlock(0, counter_win);
    }

    MPI_Bcast(&taken, 1, MPI_LONG, 0, group_comm);

    return taken + 1;
}
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
    destroy_uq_bands(&result->fim);
    destroy_uq_bands(&result->hybrid);
    SUNMatDestroy(result->media_tot);
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

#ifdef MPI
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
    MatrixArray media_matrix = {0}; // We will save transposed matrices inside the array
    SUNMatrix predicted_params_matrix = NULL;
    N_Vector initial_params = New_Serial(config->ode_expr.p_count);

    if (rank == 0)
    {
        resid_loo = NewDenseMatrix(m, n);
        // One row per leave-one-out refit. It used to have m rows with the
        // first left at zero, which dragged the median and would wreck the
        // covariance the hybrid method takes from this ensemble.
        predicted_params_matrix = NewDenseMatrix(m - 1, config->ode_expr.p_count);
        media_matrix = create_matrix_array(m - 1);
    }

    // The full-data fit. In an MPI build every rank takes part: sacess runs it
    // in parallel over the whole world.
    {
        N_Vector texp = copy_vector_remove_indices(scaled_times, create_array((long[]) {}, 0));
        SUNMatrix yexp = copy_matrix_remove_rows(observed_data, create_array((long[]) {}, 0));

        N_Vector tmp_initial_condition = copy_vector_remove_indices(initial_condition, create_array((long[]) {}, 0));

        N_Vector predicted_params = execute_ess_solver(sacess_conf_file, output_file, texp, yexp, tmp_initial_condition,
                                                       NULL, data.observed_idx);

        // The solver dimension comes from the sacess config while p_count comes
        // from the cuqdyn config. A mismatch used to overflow initial_params.
        // Every rank reads the same configs, so they all bail out together.
        if (NV_LENGTH_S(predicted_params) != NV_LENGTH_S(initial_params))
        {
            if (rank == 0)
            {
                fprintf(stderr,
                        "ERROR: the sacess config declares %ld decision variables but the cuqdyn config declares "
                        "p_count=%ld. They must match.\n",
                        NV_LENGTH_S(predicted_params), NV_LENGTH_S(initial_params));
            }
            N_VDestroy(predicted_params);
            N_VDestroy(texp);
            SUNMatDestroy(yexp);
            N_VDestroy(tmp_initial_condition);
            N_VDestroy(initial_condition);
            N_VDestroy(scaled_times);
            N_VDestroy(initial_params);
            if (rank == 0)
            {
                destroy_matrix_array(media_matrix);
            }
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
    // Every refit must start from the same point, whatever each rank's sacess
    // ended up holding.
    MPI_Bcast(NV_DATA_S(initial_params), NV_LENGTH_S(initial_params), MPI_DOUBLE, 0, MPI_COMM_WORLD);

    const LoopLayout layout = loop_layout(m - 1, nproc, rank);
    const int is_leader = rank == layout.leader;

    MPI_Comm group_comm;
    MPI_Comm_split(MPI_COMM_WORLD, (int) layout.group, rank, &group_comm);
    sacess_set_comm(group_comm);

    // The refits handed out so far. Only rank 0 exposes it.
    long refits_taken = 0;
    MPI_Win counter_win;
    MPI_Win_create(rank == 0 ? &refits_taken : NULL, rank == 0 ? (MPI_Aint) sizeof(long) : 0, sizeof(long),
                   MPI_INFO_NULL, MPI_COMM_WORLD, &counter_win);
#else
    const int is_leader = 1;
    long refits_taken = 0;
#endif

    // Only the leader of a group handles the results of its refits.
    N_Vector residuals = is_leader ? New_Serial(n) : NULL;
    RefitRecords records = {
            .n_residuals = n,
            .states_rows = NV_LENGTH_S(initial_condition),
            .states_cols = NV_LENGTH_S(scaled_times),
            .n_params = NV_LENGTH_S(initial_params),
    };

    for (;;)
    {
#ifdef MPI
        const long i = next_refit(is_leader, counter_win, group_comm);
#else
        const long i = ++refits_taken;
#endif
        if (i > m - 1)
        {
            break;
        }

        LongArray indices_to_remove = create_array((long[]) {i + 1}, 1);

        N_Vector texp = copy_vector_remove_indices(scaled_times, indices_to_remove);
        SUNMatrix yexp = copy_matrix_remove_columns(observed_data, indices_to_remove);

        N_Vector tmp_initial_condition = copy_vector_remove_indices(initial_condition, create_array((long[]) {}, 0));

        N_Vector predicted_params = execute_ess_solver(sacess_conf_file, output_file, texp, yexp, tmp_initial_condition,
                                                       initial_params, data.observed_idx);

        if (!is_leader)
        {
            N_VDestroy(predicted_params);
            continue;
        }

        // Saving the ode solution data obtained with the predicted params
        TransposedStates predicted_obs_states = solve_ode(predicted_params, initial_condition, t0, scaled_times, NULL);

        for (int j = 0; j < n_obs; ++j)
        {
            const long state = data.observed_idx[j];
            const sunrealtype observed = SM_ELEMENT_D(observed_data, j, i);
            const sunrealtype predicted = SM_ELEMENT_D(predicted_obs_states, state, i);

            NV_Ith_S(residuals, j) = fabs(observed - predicted);
        }

        append_refit_record(&records, i, residuals, predicted_obs_states, predicted_params);
        fprintf(stdout, "Refit %ld of %ld done by rank %d\n", i, m - 1, rank);

        N_VDestroy(predicted_params);
        SUNMatDestroy(predicted_obs_states);
    }

    N_VDestroy(residuals);

#ifdef MPI
    MPI_Win_free(&counter_win);
    sacess_set_comm(MPI_COMM_WORLD);
    MPI_Comm_free(&group_comm);

    // The leaders hand their results to rank 0 only now, so no group ever
    // waits on rank 0 between refits.
    if (is_leader && rank != 0)
    {
        MPI_Send(&records.count, 1, MPI_LONG, 0, 0, MPI_COMM_WORLD);
        MPI_Send(records.data, (int) (records.count * refit_record_len(&records)), MPI_DOUBLE, 0, 1, MPI_COMM_WORLD);
    }
    else if (rank == 0)
    {
        for (long group = 1; group < layout.n_groups; ++group)
        {
            const int leader = (int) share_start(nproc, layout.n_groups, group);
            long count;

            MPI_Recv(&count, 1, MPI_LONG, leader, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
            double *data_received = malloc(count * refit_record_len(&records) * sizeof(double));
            MPI_Recv(data_received, (int) (count * refit_record_len(&records)), MPI_DOUBLE, leader, 1, MPI_COMM_WORLD,
                     MPI_STATUS_IGNORE);
            store_refit_records(&records, data_received, count, resid_loo, media_matrix, predicted_params_matrix);
            free(data_received);
        }
    }
#endif

    if (rank != 0)
    {
        free(records.data);
        N_VDestroy(initial_condition);
        N_VDestroy(scaled_times);
        N_VDestroy(initial_params);
        destroy_cuqdyn_data(&data);
        release_ode_workspace();
        return NULL;
    }

    store_refit_records(&records, records.data, records.count, resid_loo, media_matrix, predicted_params_matrix);
    free(records.data);

    // media_matrix is transposed so predicted data median is also transposed
    TransposedStates predicted_data_median = matrix_array_get_median(media_matrix);

    N_Vector predicted_params_median = get_matrix_cols_median(predicted_params_matrix);
    for (int i = 0; i < NV_LENGTH_S(predicted_params_median); ++i) // Parameters are also affected by the time scaling
    {
        NV_Ith_S(predicted_params_median, i) = NV_Ith_S(predicted_params_median, i) * config->time_scaling;
    }

    const double alp = config->alp;

    // The base both varieties start from; neither ends up owning it.
    SUNMatrix q_low_base = NewDenseMatrix(m, n_states);
    SUNMatrix q_up_base = NewDenseMatrix(m, n_states);

    for (long k = 0; k < n_states; ++k)
    {
        SM_ELEMENT_D(q_low_base, 0, k) = NV_Ith_S(initial_condition, k);
        SM_ELEMENT_D(q_up_base, 0, k) = NV_Ith_S(initial_condition, k);
    }

    conformal_bands(media_matrix, resid_loo, data.observed_idx, n_obs, alp, q_low_base, q_up_base);

    /* ---- Delta-method bands for the hidden states ---------------------- */
    UqBands fim_bands = {0};
    UqBands hybrid_bands = {0};
    TransposedStates media_tot = solve_ode(initial_params, initial_condition, t0, scaled_times, NULL);

    if (media_tot == NULL)
    {
        fprintf(stderr, "ERROR: could not solve the ODE at the best-fit parameters\n");
        conformal_only_bands(q_low_base, q_up_base, m, n_states, &fim_bands, &hybrid_bands);
    }
    else if (delta_method_bands(initial_params, initial_condition, t0, scaled_times, media_tot, observed_data,
                                data.observed_idx, n_obs, predicted_params_matrix, q_low_base, q_up_base, &fim_bands,
                                &hybrid_bands) != 0)
    {
        fprintf(stderr, "ERROR: the delta-method bands are incomplete\n");
    }

    SUNMatDestroy(q_low_base);
    SUNMatDestroy(q_up_base);

    destroy_matrix_array(media_matrix);
    N_VDestroy(initial_condition);

    CuqdynResult *result = create_cuqdyn_result();

    result->predicted_data_median = predicted_data_median;
    result->predicted_params_median = predicted_params_median;
    result->fim = fim_bands;
    result->hybrid = hybrid_bands;
    result->media_tot = media_tot;
    result->parameters_init = initial_params;
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
    release_ode_workspace();

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
