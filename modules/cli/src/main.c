#include <handlers/solve.h>
#include <string.h>

#include "handlers/help.h"

int main(int argc, char *argv[])
{
    if (argc < 2)
    {
        create_help_handler().handle(argc, argv);
        return 0;
    }

    Handler handler;

    if (strcmp(argv[1], "solve") == 0)
    {
        handler = create_solve_handler();
    }else
    {
        handler = create_help_handler();
    }

    handler.handle(argc, argv);

    return 0;
}
