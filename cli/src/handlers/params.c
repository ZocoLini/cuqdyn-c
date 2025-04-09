#include <stdio.h>
#include <unistd.h>

void handle_params(int argc, char *argv[])
{
    int opt;
    while ((opt = getopt(argc, argv, "f:o:v")) != -1) {
        switch (opt) {
            case 'f':
                printf("Archivo: %s\n", optarg);
            break;
            case 'o':
                printf("Salida: %s\n", optarg);
            break;
            case 'v':
                printf("Modo verbose\n");
            break;
            default:
                fprintf(stderr, "Uso: %s [-f archivo] [-o salida] [-v]\n", argv[0]);
        }
    }
}