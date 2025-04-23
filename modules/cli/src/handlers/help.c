#include <stdio.h>
#include "handlers/handlers.h"

int handle_help(int argc, char *argv[]);

Handler create_help_handler()
{
    Handler handler;
    handler.handle = handle_help;
    return handler;
}

int handle_help(int argc, char *argv[])
{
    const char* help_message =
"cuqdyn-c v%s - A rewrite of the ... (by Borja Castellano)\n"
"\n"
"- [ Commands ] -\n"
"\n"
" Command   | Description                                                         \n"
"==========+======================================================================\n"
" solve     | Solves the given problem with the given configuration and data      \n"
" version   | Displays the current version of the tool                            \n"
" help      | Displays this help message                                          \n"
"\n"
"- [ Solve command options ] -\n"
"\n"
" Options Short    | Type | Description                                                     | Default value   |Example\n"
" =================+======+================================================================+==================+=====================\n"
" -c               | Str  | Path to the cuqdyn xml config file                              |                 |-c config/cuqdyn_conf.xml\n"
" -s               | Str  | Path to the sacess library xml config file                      |                 |-s config/sacess_library_conf.xml\n"
" -d               | Str  | Path to the data file (Supports text and .mat files)            |                 |-d data/lotka_volterra.txt\n"
" -o               | Str  | Defines the output folder for the results                       | output          |-o output\n"
"\n"
"Usage: %s [command] [options]...\n";


    printf(help_message, "0.1.0", argv[0]);
    return 0;
}
