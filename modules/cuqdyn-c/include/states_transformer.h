//
// Created by borja on 12/06/25.
//

#ifndef STATES_TRANSFORMER_H
#define STATES_TRANSFORMER_H
#include <sunmatrix/sunmatrix_dense.h>
#include "cuqdyn.h"

/// This function destroys the transposed state matrix and returns a new transposed matrix with the observables
/// states if a transformation expr is defined in the config XML.
ObservablesTransposedStates transform_states(TransposedStates states);

#endif //STATES_TRANSFORMER_H
