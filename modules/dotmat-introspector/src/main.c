#include <matio.h>

int main(int argc, char *argv[])
{
    if (argc != 2)
    {
        fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
        return 1;
    }

    mat_t *matfp;
    matvar_t *matvar;
    char *filename = argv[1];

    // Abrir archivo .mat
    matfp = Mat_Open(filename, MAT_ACC_RDONLY);
    if (matfp == NULL)
    {
        fprintf(stderr, "Can't open the file %s\n", filename);
        return 1;
    }

    // Leer la primera variable del archivo
    matvar = Mat_VarReadNext(matfp);
    while (matvar != NULL)
    {
        printf("Variable name: %s\n", matvar->name);
        printf("Dims: ");
        for (size_t i = 0; i < matvar->rank; i++)
        {
            printf("%zu ", matvar->dims[i]);
        }
        printf("\nData type: %d\n", matvar->data_type);

        Mat_VarFree(matvar);
        matvar = Mat_VarReadNext(matfp);
    }

    Mat_Close(matfp);
    return 0;
}
