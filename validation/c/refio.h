/*
 * Readers for the packed reference files of layers 1-4 (validation/references).
 *
 * A reference file is a sequence of sections. A section starts with a line
 * "[name]" and holds either one array (a "rows cols" or "n1 n2 n3" header,
 * then the values row by row) or "key value" lines. open_section() positions
 * a stream right after the header line of a section; the token readers of
 * textio.h take it from there. A truncated section fails in those readers,
 * because the next token they meet is the following "[name]" line, which is
 * not a number.
 */
#ifndef VALIDATION_REFIO_H
#define VALIDATION_REFIO_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Strips the line terminator and trailing blanks of a line read with fgets. */
static inline void chomp(char *line)
{
    size_t n = strlen(line);
    while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r' || line[n - 1] == ' ' || line[n - 1] == '\t'))
    {
        line[--n] = '\0';
    }
}

/* 1 when line is exactly "[name]". */
static inline int is_section_header(const char *line, const char *name)
{
    const size_t n = strlen(name);
    return line[0] == '[' && strncmp(line + 1, name, n) == 0 && line[n + 1] == ']' && line[n + 2] == '\0';
}

/*
 * Opens path and positions the stream after the line "[name]". With required
 * set, a missing file or section is fatal; otherwise NULL says it is absent.
 */
static inline FILE *open_section(const char *path, const char *name, int required)
{
    FILE *f = fopen(path, "r");
    if (f == NULL)
    {
        if (required)
        {
            fprintf(stderr, "ERROR: cannot open %s\n", path);
            exit(2);
        }
        return NULL;
    }

    char line[4096];
    while (fgets(line, sizeof(line), f) != NULL)
    {
        chomp(line);
        if (is_section_header(line, name))
        {
            return f;
        }
    }
    fclose(f);

    if (required)
    {
        fprintf(stderr, "ERROR: no section [%s] in %s\n", name, path);
        exit(2);
    }
    return NULL;
}

static inline int section_exists(const char *path, const char *name)
{
    FILE *f = open_section(path, name, 0);
    if (f == NULL)
    {
        return 0;
    }
    fclose(f);
    return 1;
}

/*
 * Reads the next "key value" line of the current section. The value keeps its
 * inner blanks ("matlab_version 24.2.0 (R2024b)"). Returns 0 at the end of the
 * section or of the file.
 */
static inline int read_kv_line(FILE *f, char *key, size_t key_len, char *value, size_t value_len)
{
    char line[4096];
    while (fgets(line, sizeof(line), f) != NULL)
    {
        chomp(line);
        if (line[0] == '[')
        {
            return 0;
        }
        char *p = line;
        while (*p == ' ' || *p == '\t')
        {
            p++;
        }
        if (*p == '\0')
        {
            continue;
        }
        char *sep = p;
        while (*sep != '\0' && *sep != ' ' && *sep != '\t')
        {
            sep++;
        }
        size_t klen = (size_t) (sep - p);
        if (klen >= key_len)
        {
            klen = key_len - 1;
        }
        memcpy(key, p, klen);
        key[klen] = '\0';
        while (*sep == ' ' || *sep == '\t')
        {
            sep++;
        }
        snprintf(value, value_len, "%s", sep);
        return 1;
    }
    return 0;
}

/* Looks a key up in a "key value" section. Returns 0 when the section or the
 * key is absent. */
static inline int lookup_kv(const char *path, const char *section, const char *key, char *out, size_t out_len)
{
    FILE *f = open_section(path, section, 0);
    if (f == NULL)
    {
        return 0;
    }
    char k[256], v[1024];
    int found = 0;
    while (read_kv_line(f, k, sizeof(k), v, sizeof(v)))
    {
        if (strcmp(k, key) == 0)
        {
            snprintf(out, out_len, "%s", v);
            found = 1;
            break;
        }
    }
    fclose(f);
    return found;
}

/*
 * Reads the next name of a list section (one name per line, no blanks in a
 * name). Returns 0 at the end of the section or of the file.
 */
static inline int read_name(FILE *f, char *out, size_t out_len)
{
    char token[256];
    if (fscanf(f, "%255s", token) != 1 || token[0] == '[')
    {
        return 0;
    }
    snprintf(out, out_len, "%s", token);
    return 1;
}

#endif
