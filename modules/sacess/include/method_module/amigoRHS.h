#include <math.h>
#include <nvector_old/nvector_serial.h>
#include <sundials_old/sundials_direct.h>
/* *** Definition of the algebraic variables *** */

/* Right hand side of the system (f(t,x,p))*/
int amigoRHS_CIRCADIAN(realtype , N_Vector , N_Vector , void *);

/* Jacobian of the system (dfdx)*/
int amigoJAC_CIRCADIAN(int , realtype , N_Vector , N_Vector , DlsMat , void *, N_Vector , N_Vector , N_Vector );

/* R.H.S of the sensitivity dsi/dt = (df/dx)*si + df/dp_i */
int amigoSensRHS_CIRCADIAN(int , realtype , N_Vector , N_Vector , int , N_Vector , N_Vector , void *, N_Vector , N_Vector );

void amigoRHS_get_OBS_CIRCADIAN(void* );

void amigoRHS_get_sens_OBS_CIRCADIAN(void* );

void amigo_Y_at_tcon_CIRCADIAN(void* , realtype , N_Vector );

/* *** Definition of the algebraic variables *** */

/* Right hand side of the system (f(t,x,p))*/
int amigoRHS_MENDES(realtype , N_Vector , N_Vector , void *);

/* Jacobian of the system (dfdx)*/
int amigoJAC_MENDES(int , realtype , N_Vector , N_Vector , DlsMat , void *, N_Vector , N_Vector , N_Vector);

/* R.H.S of the sensitivity dsi/dt = (df/dx)*si + df/dp_i */
int amigoSensRHS_MENDES(int , realtype , N_Vector , N_Vector , int , N_Vector , N_Vector , void *, N_Vector , N_Vector);

void amigoRHS_get_OBS_MENDES(void* );

void amigoRHS_get_sens_OBS_MENDES(void* );


void amigo_Y_at_tcon_MENDES(void* , realtype , N_Vector );

/* *** Definition of the algebraic variables *** */

/* Right hand side of the system (f(t,x,p))*/
int amigoRHS_NFKB(realtype , N_Vector , N_Vector , void *);

/* Jacobian of the system (dfdx)*/
int amigoJAC_NFKB(int N, realtype t, N_Vector y, N_Vector fy, DlsMat J, void *data, N_Vector tmp1, N_Vector tmp2, N_Vector );

/* R.H.S of the sensitivity dsi/dt = (df/dx)*si + df/dp_i */
int amigoSensRHS_NFKB(int , realtype , N_Vector , N_Vector , int , N_Vector , N_Vector , void *, N_Vector, N_Vector);

void amigoRHS_get_OBS_NFKB(void* );

void amigoRHS_get_sens_OBS_NFKB(void* );

void amigo_Y_at_tcon_NFKB(void* , realtype , N_Vector );



int amigoRHS_LOGIC(realtype t, N_Vector y, N_Vector ydot, void *data);

void amigoRHS_get_OBS_LOGIC(void* data);

void amigoRHS_get_sens_OBS_LOGIC(void* data);
 
void amigo_Y_at_tcon_LOGIC(void* data,realtype t, N_Vector y);


/* Right hand side of the system (f(t,x,p))*/
int amigoRHS_DREAMBT20(realtype , N_Vector , N_Vector , void *);

void amigoRHS_get_sens_OBS_DREAMBT20(void* );

void amigoRHS_get_OBS_DREAMBT20(void* );

void amigo_Y_at_tcon_DREAMBT20(void* , realtype , N_Vector );

