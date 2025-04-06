#include <stdio.h>

#include "lotka_volterra.h"
#include "math.h"

/* Data matrix format with as many rows as time points and as many columns as observables + 1
 * [time, y1, y2, ..., yn]
 *
 */

int main(void)
{
    solve_lotka_volterra();

    return 0;
}
