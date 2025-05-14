#include <stdio.h>

#include "cuqdyn.h"
#include "nvector_old/nvector_serial.h"
#include "sundials_old/sundials_nvector.h"

typedef struct MuParserHandle MuParserHandle;

MuParserHandle *muparser_create();
void muparser_destroy(MuParserHandle *handle);
int muparser_define_var(MuParserHandle *handle, const char *name, double *ptr);
int muparser_set_expr(MuParserHandle *handle, const char *expr);
double muparser_eval(MuParserHandle *handle);

// Each line should be defined in the glocal configuration and iterated here
int custom_f(realtype t, N_Vector y, N_Vector ydot, void *user_data)
{
    realtype y1, y2;

    y1 = MIth(y, 1);
    y2 = MIth(y, 2);

    realtype *data = N_VGetArrayPointer(user_data);

    MuParserHandle *p1 = muparser_create();
    MuParserHandle *p2 = muparser_create();

    muparser_define_var(p1, "y1", &y1);
    muparser_define_var(p1, "y2", &y2);
    muparser_define_var(p1, "p1", &data[0]);
    muparser_define_var(p1, "p2", &data[1]);
    muparser_set_expr(p1, "y1 * (p1 - p2 * y2)");

    muparser_define_var(p2, "y1", &y1);
    muparser_define_var(p2, "y2", &y2);
    muparser_define_var(p2, "p3", &data[2]);
    muparser_define_var(p2, "p4", &data[3]);
    muparser_set_expr(p2, "-y2 * (p3 - p4 * y1)");

    MIth(ydot, 1) = muparser_eval(p1);
    MIth(ydot, 2) = muparser_eval(p2);

    muparser_destroy(p1);
    muparser_destroy(p2);

    return 0;
}
