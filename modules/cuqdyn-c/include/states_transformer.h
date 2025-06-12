//
// Created by borja on 12/06/25.
//

#ifndef STATES_TRANSFORMER_H
#define STATES_TRANSFORMER_H
#include <sunmatrix/sunmatrix_dense.h>

/// This function destroys the state matrix and returns a new matrix with the transformed states if the
/// transformation expr is defined in the config XML.
SUNMatrix transform_states(SUNMatrix states);

#endif //STATES_TRANSFORMER_H
