#include <stdio.h>
#include "handlers.h"

void handle_help(int argc, char *argv[]);

Handler create_help_handler()
{
    Handler handler;
    handler.handle = handle_help;
    return handler;
}

void handle_help(int argc, char *argv[])
{
    const char* help_message =
"db-sniffer v{version} - A database introspector tool (by Borja Castellano)\n"
"\n"
"- [ Commands ] -\n"
"\n"
" Command   | Description                                         \n"
"==========+======================================================\n"
" sniff     | Introspects a database and outputs the results      \n"
" version   | Displays the current version of the tool            \n"
" help      | Displays this help message                          \n"
"\n"
"- [ Options ] -\n"
"\n"
" Options Short    | Type | Description                                                     | Example\n"
" =================+======+================================================================+=======================\n"
" -u               | Str  | Define the connection string to the database                    | -u mysql://user:pass@ip:port/db\n"
" -m               | Num  | Indicates the generation mode                                   | -m 1\n"
" -o               | Str  | Defines the output variable of the generation mode (optional)   | -o src/main/java/com/example/entities\n"
"\n"
"- [ Generation modes ] -\n"
"\n"
"  Mode | Name\n"
" ======+======\n"
"     0 | DDL (Not implemented)\n"
"     1 | Hibernate HBM.XML\n"
"     2 | Hibernate with JPA Annotations (Not implemented)\n"
"\n"
"Usage: sniffer [command] [options]...\n";


    printf("%s", help_message);
}
