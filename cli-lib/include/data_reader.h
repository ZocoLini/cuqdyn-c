#ifndef FILE_READER_H
#define FILE_READER_H

#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

int read_txt_data_file(const char *data_file, N_Vector *t, SUNMatrix *y, sunrealtype *t0, N_Vector *y0);
int read_mat_data_file(const char *data_file, N_Vector *t, SUNMatrix *y, sunrealtype *t0, N_Vector *y0);

#endif //FILE_READER_H
