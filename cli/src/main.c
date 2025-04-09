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

    if (strcmp(argv[1], "help") == 0)
    {
        handle_help(argc, argv);
    } else if (strcmp(argv[1], "params") == 0)
    {
        handle_params(argc, argv);
    }else
    {
        printf("Unknown command: %s\n", argv[1]);
        handle_help(argc, argv);
    }

    return 0;
}
