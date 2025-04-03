//
// Created by borja on 03/04/25.
//

#ifndef LIB_H
#define LIB_H

#include "math.h"

void solve_ode(struct Matrix, struct Matrix, struct Matrix);

void prob_mod_dynamics_ap(double*, double*, double*);
void prob_mod_dynamics_log(double*, double*, double*);
void prob_mod_dynamics_lv(double*, double*, double*);

#endif //LIB_H
