/*
 * File:   serSolvers.h
 * Author: david
 *
 * Created on 6 de junio de 2013, 12:09
 */

#ifndef SERSOLVERS_H
#define SERSOLVERS_H

#ifdef __cplusplus
extern "C"
{
#endif

// NEW: Fixed wrong header and function implementations. GCC was doing wrong optimizations due to this

#include <method_module/structure_paralleltestbed.h>
    int execute_Solver(experiment_total *, result_solver *, void *function(double *, void *));
    int execute_serial_solver(experiment_total *, result_solver *, long, double, void *function(double *, void *));
    int execute_parallel_solver(experiment_total *, result_solver *, long, double, void *function(double *, void *));

#ifdef __cplusplus
}
#endif

#endif /* SERSOLVERS_H */
