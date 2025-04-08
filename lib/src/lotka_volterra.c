
#include <sundials/sundials_nvector.h>
#include <sundials/sundials_types.h>

#include "lib.h"

int lotka_volterra_f(sunrealtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    sunrealtype y1, y2;

    y1 = Ith(y, 1);
    y2 = Ith(y, 2);

    sunrealtype *data = N_VGetArrayPointer(user_data);

    Ith(ydot, 1) = y1 * (SUN_RCONST(data[0]) - SUN_RCONST(data[1]) * y2);
    Ith(ydot, 2) = -y2 * (SUN_RCONST(data[2]) - SUN_RCONST(data[3]) * y1);

    return (0);
}