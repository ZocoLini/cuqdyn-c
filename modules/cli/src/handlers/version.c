#include <handlers/handlers.h>
#include <stdio.h>

#include "cuqdyn_version.h"
#include "sacess_version.h"

int handle_version(int argc, char *argv[]);

Handler create_version_handler()
{
    Handler handler;
    handler.handle = handle_version;
    return handler;
}

int handle_version(int argc, char *argv[])
{
    const char *help_message = "- [Version] -\n"
                               "cli %s — Command line interface for the CUQDYN algorithm (by Borja Castellano)\n"
                               "cuqdyn-c %s — C implementation of the CUQDYN algorithm (by Borja Castellano)\n"
                               "sacess %s — C implementation of the Scatter Search algorithm\n";

    return printf(help_message, CLI_VERSION, CUQDYN_C_VERSION, SACESS_C_VERSION);
}
