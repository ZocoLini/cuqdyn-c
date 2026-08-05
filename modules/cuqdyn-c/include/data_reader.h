#ifndef FILE_READER_H
#define FILE_READER_H

#include <sundials/sundials_nvector.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "cuqdyn.h"

/*
 * Observed data plus the observability pattern.
 *
 * Measured states get distribution-free conformal bands and the rest get
 * Gaussian delta-method ones, so every stage downstream needs to know which is
 * which. Matrices follow the transposed convention used across the library:
 * rows are states, columns are time points.
 */
typedef struct
{
    N_Vector times;              // length m
    ObservedData all_state_data; // n_states x m, NaN where a state is unmeasured
    ObservedData observed_data;  // n_obs x m, the measured rows only
    N_Vector initial_values;     // length n_states, finite for every state

    int *observed_idx; // 0-based state indices, ascending, length n_obs
    int n_obs;
    long n_states;
    long m;
} CuqdynData;

void destroy_cuqdyn_data(CuqdynData *data);

/*
 * The file should be two ints, m and n, and a matrix mxn
 *      m n
 *      <matrix>
 * All the data contained in the matrix is the observed data and has this form:
 *      t0 y00 y01 y02 ... y0n
 *      t1 y10 y11 y12 ... y1n
 *      .                   .
 *      .                   .
 *      .                   .
 *      tm ym0 ym1 ym2 ... ymn
 *
 * The time vector is the first column of the matrix [t0, t1, t2, ..., tm] and
 * every column after it is a model state, in order: y1, y2, ... yn.
 *
 * A state that is never measured carries NaN from t > 0 onwards. That is the
 * only thing that marks a state as unobserved; a file without NaN is fully
 * observed. Row 1 must be finite for every state, hidden ones included, since
 * it is the initial condition.
 */
int read_data_file(const char *data_file, CuqdynData *data);

#endif // FILE_READER_H
