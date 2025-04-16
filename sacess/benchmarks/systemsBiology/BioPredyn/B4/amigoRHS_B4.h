#include <math.h>
#include <nvector_old/nvector_serial.h>
#include <sundials_old/sundials_direct.h>

int amigoRHS_B4(realtype t, N_Vector y, N_Vector ydot, void *data);

void amigoRHS_get_OBS_B4(void* data);

void amigoRHS_get_sens_OBS_B4(void* data);
 
int amigoRHS_B4(realtype t, N_Vector y, N_Vector ydot, void *data);

void amigo_Y_at_tcon_B4(void* amigo_model, realtype t, N_Vector y);
