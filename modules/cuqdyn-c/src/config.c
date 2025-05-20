#include "config.h"

#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlstring.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <cuqdyn.h>

static CuqdynConf *config = NULL;

CuqdynConf *create_cuqdyn_conf(Tolerances tolerances, OdeExpr ode_expr)
{
    CuqdynConf *cuqdyn_conf = malloc(sizeof(CuqdynConf));
    cuqdyn_conf->tolerances = tolerances;
    cuqdyn_conf->ode_expr = ode_expr;
    return cuqdyn_conf;
}

void destroy_cuqdyn_conf()
{
    if (config == NULL)
    {
        return;
    }

    destroy_tolerances(config->tolerances);
    destroy_ode_expr(config->ode_expr);
    free(config);
    config = NULL;
}

CuqdynConf *init_cuqdyn_conf_from_file(const char *filename)
{
    CuqdynConf *tmp_config = malloc(sizeof(CuqdynConf));
    if (tmp_config == NULL)
    {
        fprintf(stderr, "ERROR: Memory allocation failed in function "
                        "init_cuqdyn_conf_from_file()\n");
        exit(1);
    }

    int flag = parse_cuqdyn_conf(filename, tmp_config);

    if (flag != 0)
    {
        fprintf(stderr, "ERROR: Unable to parse cuqdyn config file \"%s\"\n", filename);
        exit(1);
    }

    config = tmp_config;
    return config;
}

int parse_cuqdyn_conf(const char *filename, CuqdynConf *config)
{
    xmlDocPtr doc = xmlReadFile(filename, NULL, 0);
    if (!doc)
    {
        fprintf(stderr, "Error: could not load XML file: %s\n", filename);
        return -1;
    }

    xmlNodePtr root = xmlDocGetRootElement(doc);
    xmlNodePtr cur = root->children;

    realtype rtol = 1e-6;
    N_Vector atol = NULL;
    int y_count = 0;
    char **odes = NULL;
    int p_count = 0;

    for (; cur; cur = cur->next)
    {
        if (cur->type != XML_ELEMENT_NODE)
            continue;

        if (!xmlStrcmp(cur->name, "tolerances"))
        {
            xmlNodePtr tolNode = cur->children;
            for (; tolNode; tolNode = tolNode->next)
            {
                if (tolNode->type != XML_ELEMENT_NODE)
                    continue;

                if (!xmlStrcmp(tolNode->name, "rtol"))
                {
                    xmlChar *key = xmlNodeGetContent(tolNode);
                    rtol = atof((char *) key);
                    xmlFree(key);
                }
                else if (!xmlStrcmp(tolNode->name, "atol"))
                {
                    xmlChar *key = xmlNodeGetContent(tolNode);
                    char *key_str = (char *) key;

                    // Primera pasada: contar elementos
                    size_t count = 0;
                    char *tmp1 = strdup(key_str);
                    char *token = strtok(tmp1, ",");
                    while (token)
                    {
                        count++;
                        token = strtok(NULL, ",");
                    }
                    free(tmp1);

                    atol = N_VNew_Serial(count);
                    if (!atol)
                    {
                        fprintf(stderr, "Error: failed to allocate atol N_Vector\n");
                        xmlFree(key);
                        xmlFreeDoc(doc);
                        return -1;
                    }

                    // Segunda pasada: parsear los valores
                    size_t i = 0;
                    char *tmp2 = strdup(key_str);
                    token = strtok(tmp2, ",");
                    while (token && i < count)
                    {
                        NV_Ith_S(atol, i++) = atof(token);
                        token = strtok(NULL, ",");
                    }
                    free(tmp2);
                    xmlFree(key);
                }
            }
        }
        else if (!xmlStrcmp(cur->name, "ode_expr"))
        {
            xmlChar *y_count_attr = xmlGetProp(cur, "y_count");
            if (y_count_attr == NULL)
            {
                fprintf(stderr, "Error: <ode_expr> node does not have a 'y_count' attribute\n");
                xmlFreeDoc(doc);
                return 1;
            }

            y_count = atoi((char *) y_count_attr);
            xmlFree(y_count_attr);

            xmlChar *p_count_attr = xmlGetProp(cur, "p_count");
            if (p_count_attr == NULL)
            {
                fprintf(stderr, "Error: <ode_expr> node does not have a 'p_count' attribute\n");
                xmlFreeDoc(doc);
                return 1;
            }

            p_count = atoi((char *) p_count_attr);
            xmlFree(p_count_attr);

            xmlChar *content = xmlNodeGetContent(cur);
            if (content == NULL)
            {
                fprintf(stderr, "Error: no content in <odes> node\n");
                xmlFreeDoc(doc);
                return 1;
            }

            char *odes_str = (char *) content;

            char *token = strtok(odes_str, "\n");

            odes = calloc(y_count, sizeof(char *));

            int index = 0;
            while (token != NULL)
            {
                while (*token == ' ')
                    token++;

                if (*token != '\0')
                {
                    odes[index] = token;
                    index++;
                }
                token = strtok(NULL, "\n");
            }
        }
    }

    config->tolerances = create_tolerances(rtol, atol);
    config->ode_expr = create_ode_expr(y_count, p_count, odes);
    xmlFreeDoc(doc);
    return 0;
}

CuqdynConf *init_cuqdyn_conf(Tolerances tolerances, OdeExpr ode_expr)
{
    destroy_cuqdyn_conf();

    config = create_cuqdyn_conf(tolerances, ode_expr);
    return config;
}

CuqdynConf *get_cuqdyn_conf()
{
    if (config == NULL)
    {
        fprintf(stderr, "ERROR: cuqdyn config not initialized. Call "
                        "init_cuqdyn_conf_from_file() first.\n");
        exit(1);
    }

    return config;
}

Tolerances create_tolerances(realtype scalar_rtol, N_Vector atol)
{
    Tolerances tolerances;
    tolerances.rtol = scalar_rtol;
    tolerances.atol = atol;
    return tolerances;
}

void destroy_tolerances(Tolerances tolerances) { N_VDestroy(tolerances.atol); }

OdeExpr create_ode_expr(int y_count, int p_count, char **exprs)
{
    OdeExpr odeExpr;
    odeExpr.exprs = exprs;
    odeExpr.y_count = y_count;
    odeExpr.p_count = p_count;
    return odeExpr;
}

void destroy_ode_expr(OdeExpr ode_expr) {}
