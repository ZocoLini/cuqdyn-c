#include "muParser.h"
#include <cstring>

extern "C" {

    typedef struct {
        mu::Parser *parser;
    } MuParserHandle;

    MuParserHandle* muparser_create() {
        MuParserHandle *handle = new MuParserHandle;
        handle->parser = new mu::Parser();
        return handle;
    }

    void muparser_destroy(MuParserHandle *handle) {
        delete handle->parser;
        delete handle;
    }

    int muparser_define_var(MuParserHandle *handle, const char *name, double *ptr) {
        try {
            handle->parser->DefineVar(name, ptr);
            return 0;
        } catch (...) {
            return 1;
        }
    }

    int muparser_set_expr(MuParserHandle *handle, const char *expr) {
        try {
            handle->parser->SetExpr(expr);
            return 0;
        } catch (...) {
            return 1;
        }
    }

    double muparser_eval(MuParserHandle *handle) {
        return handle->parser->Eval();
    }

}
