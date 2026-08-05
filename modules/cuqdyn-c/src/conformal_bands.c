#include "uq_bands.h"

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "cuqdyn.h"
#include "matlab.h"

void conformal_bands(const MatrixArray media_matrix, SUNMatrix resid_loo, const int *observed_idx, const int n_obs,
                     const double alp, SUNMatrix q_low, SUNMatrix q_up)
{
    const long m = SM_ROWS_D(q_low);

    // One shifted copy of the ensemble is reused for every point and band.
    N_Vector shifted = New_Serial(m - 1);

    for (int j = 0; j < n_obs; ++j)
    {
        const long state = observed_idx[j];

        for (long i = 1; i < m; ++i)
        {
            for (long k = 1; k < m; ++k)
            {
                NV_Ith_S(shifted, k - 1) = SM_ELEMENT_D(matrix_array_get_index(media_matrix, k - 1), state, i) -
                                           SM_ELEMENT_D(resid_loo, k, j);
            }
            SM_ELEMENT_D(q_low, i, state) = quantile(shifted, alp);

            for (long k = 1; k < m; ++k)
            {
                NV_Ith_S(shifted, k - 1) = SM_ELEMENT_D(matrix_array_get_index(media_matrix, k - 1), state, i) +
                                           SM_ELEMENT_D(resid_loo, k, j);
            }
            SM_ELEMENT_D(q_up, i, state) = quantile(shifted, 1 - alp);
        }
    }

    N_VDestroy(shifted);
}
