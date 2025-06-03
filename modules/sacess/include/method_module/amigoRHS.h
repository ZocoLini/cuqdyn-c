#include <math.h>
#include <nvector/nvector_serial.h>
#include <sundials/sundials_direct.h>
/* *** Definition of the algebraic variables *** */

/* Right hand side of the system (f(t,x,p))*/
int amigoRHS_CIRCADIAN(sunrealtype , N_Vector , N_Vector , void *);

/* Jacobian of the system (dfdx)*/
int amigoJAC_CIRCADIAN(int , sunrealtype , N_Vector , N_Vector , SUNMatrix , void *, N_Vector , N_Vector , N_Vector );

/* R.H.S of the sensitivity dsi/dt = (df/dx)*si + df/dp_i */
int amigoSensRHS_CIRCADIAN(int , sunrealtype , N_Vector , N_Vector , int , N_Vector , N_Vector , void *, N_Vector , N_Vector );

void amigoRHS_get_OBS_CIRCADIAN(void* );

void amigoRHS_get_sens_OBS_CIRCADIAN(void* );

void amigo_Y_at_tcon_CIRCADIAN(void* , sunrealtype , N_Vector );

/* *** Definition of the algebraic variables *** */

/* Right hand side of the system (f(t,x,p))*/
int amigoRHS_MENDES(sunrealtype , N_Vector , N_Vector , void *);

/* Jacobian of the system (dfdx)*/
int amigoJAC_MENDES(int , sunrealtype , N_Vector , N_Vector , SUNMatrix , void *, N_Vector , N_Vector , N_Vector);

/* R.H.S of the sensitivity dsi/dt = (df/dx)*si + df/dp_i */
int amigoSensRHS_MENDES(int , sunrealtype , N_Vector , N_Vector , int , N_Vector , N_Vector , void *, N_Vector , N_Vector);

void amigoRHS_get_OBS_MENDES(void* );

void amigoRHS_get_sens_OBS_MENDES(void* );


void amigo_Y_at_tcon_MENDES(void* , sunrealtype , N_Vector );

/* *** Definition of the algebraic variables *** */

/* Right hand side of the system (f(t,x,p))*/
int amigoRHS_NFKB(sunrealtype , N_Vector , N_Vector , void *);

/* Jacobian of the system (dfdx)*/
int amigoJAC_NFKB(int N, sunrealtype t, N_Vector y, N_Vector fy, SUNMatrix J, void *data, N_Vector tmp1, N_Vector tmp2, N_Vector );

/* R.H.S of the sensitivity dsi/dt = (df/dx)*si + df/dp_i */
int amigoSensRHS_NFKB(int , sunrealtype , N_Vector , N_Vector , int , N_Vector , N_Vector , void *, N_Vector, N_Vector);

void amigoRHS_get_OBS_NFKB(void* );

void amigoRHS_get_sens_OBS_NFKB(void* );

void amigo_Y_at_tcon_NFKB(void* , sunrealtype , N_Vector );



int amigoRHS_LOGIC(sunrealtype t, N_Vector y, N_Vector ydot, void *data);

void amigoRHS_get_OBS_LOGIC(void* data);

void amigoRHS_get_sens_OBS_LOGIC(void* data);
 
void amigo_Y_at_tcon_LOGIC(void* data,sunrealtype t, N_Vector y);


/* Right hand side of the system (f(t,x,p))*/
int amigoRHS_DREAMBT20(sunrealtype , N_Vector , N_Vector , void *);

void amigoRHS_get_sens_OBS_DREAMBT20(void* );

void amigoRHS_get_OBS_DREAMBT20(void* );

void amigo_Y_at_tcon_DREAMBT20(void* , sunrealtype , N_Vector );

