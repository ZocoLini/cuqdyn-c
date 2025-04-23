#include <stdio.h>
#include <string.h>
#include "handlers/help.h"
#include "handlers/params.h"

int main(int argc, char *argv[])
{
    if (argc < 2)
    {
        printf("Use: %s <command> [options]\n", argv[0]);
        return 1;
    }

#ifdef MPI2
    int err = MPI_Init(&argc, &argv);

    if (err != MPI_SUCCESS) {
        fprintf(stderr, "MPI_Init failed\n");
        exit(1);
    }
#endif

    Handler handler;

    if (strcmp(argv[1], "params") == 0)
    {
        handler = create_params_handler();
    }else
    {
        handler = create_help_handler();
    }

    handler.handle(argc, argv);

    return 0;
}
