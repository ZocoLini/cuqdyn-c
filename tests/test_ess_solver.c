#define CONF_FILE "data/ess_config.xml"
#define BBOB_CONF_FILE "data/TEMPLATE_BBOB.xml"
#define OUPUT_PATH "data/ess_output"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <tgmath.h>

#include "ess_solver.h"
#include "method_module/structure_paralleltestbed.h"
#include "lib.h"

void test_1();

void* examplefunction(double *x, void *data) {
    // Initialize mandatory structs
    experiment_total *exp1;
    output_function *res;
    int dim;
    exp1 = (experiment_total *) data;
    res = NULL;
    res = (output_function *) calloc(1,sizeof(output_function));
    dim = (*exp1).test.bench.dim;
    // Objective function code: in this example Schwefel
    double y, sum;
    int i;
    sum = 0.0;
    for (i=0;i<dim;i++){
        sum = sum + x[i]*sin(sqrt(abs(x[i])));
    }
    y = 418.9829*dim - sum;
    // Return fx: set the fx in output_function struct
    // and return like a void pointer
    res->value = y;

    return res;
}

int main(int argc, char** argv)
{
    test_1();
    printf("\tTest 1 passed\n");

    return 0;
}

void test_1()
{
    execute_ess_solver(CONF_FILE, OUPUT_PATH, examplefunction);
}