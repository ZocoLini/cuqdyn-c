//
// Created by borja on 11/04/25.
//

#ifndef HANDLERS_H
#define HANDLERS_H

typedef struct
{
    int (*handle)(int argc, char *argv[]);
} Handler;

#endif //HANDLERS_H
