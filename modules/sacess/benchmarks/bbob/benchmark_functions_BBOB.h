#include <method_module/structure_paralleltestbed.h>
#include <bbob/bbobStructures.h>

int initializeBBOB(experiment_total *, const char*);

int updateFunctionsBBOB(experiment_total *, int, int);

int destroyBBOB(experiment_total *);

void* fgeneric_noise(double * X, void *data);

void* fgeneric_noiseless(double * X, void *data);