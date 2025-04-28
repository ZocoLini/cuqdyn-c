#include <assert.h>
#include <time.h>


#include "config.h"
void main(void)
{
    TimeConstraints time_constraints = create_time_constraints(1.0, 5.0, 0.5);
    assert(time_constraints_steps(time_constraints) == 8);
    printf("\tTest 1 passed\n");

    time_constraints = create_time_constraints(4.0, 5.0, 0.1);
    assert(time_constraints_steps(time_constraints) == 10);
    printf("\tTest 2 passed\n");

    time_constraints = create_time_constraints(0.0, 30.0, 1.0);
    assert(time_constraints_steps(time_constraints) == 30);
    printf("\tTest 3 passed\n");
}