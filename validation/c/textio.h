/*
 * Checked text-to-number readers for the validation harnesses.
 *
 * fscanf("%ld") and atof() cannot report a malformed token, so a truncated or
 * hand-edited reference file would be read as zeros and compared in silence.
 * Every reader here parses a whitespace-delimited token with strtol/strtod and
 * fails unless the whole token was consumed.
 */
#ifndef VALIDATION_TEXTIO_H
#define VALIDATION_TEXTIO_H

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

static inline int parse_long(const char *s, long *out)
{
    char *end = NULL;
    errno = 0;
    const long v = strtol(s, &end, 10);
    if (end == s || *end != '\0' || errno == ERANGE)
    {
        return 0;
    }
    *out = v;
    return 1;
}

static inline int parse_double(const char *s, double *out)
{
    char *end = NULL;
    errno = 0;
    const double v = strtod(s, &end);
    if (end == s || *end != '\0' || errno == ERANGE)
    {
        return 0;
    }
    *out = v;
    return 1;
}

static inline int read_long(FILE *f, long *out)
{
    char token[256];
    return fscanf(f, "%255s", token) == 1 && parse_long(token, out);
}

static inline int read_int(FILE *f, int *out)
{
    long v;
    if (!read_long(f, &v) || v < INT_MIN || v > INT_MAX)
    {
        return 0;
    }
    *out = (int) v;
    return 1;
}

static inline int read_double(FILE *f, double *out)
{
    char token[256];
    return fscanf(f, "%255s", token) == 1 && parse_double(token, out);
}

#endif
