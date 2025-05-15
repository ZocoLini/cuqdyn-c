#include "config.h"

#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlstring.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <cuqdyn.h>

static CuqdynConf *config = NULL;

CuqdynConf *create_cuqdyn_conf(Tolerances tolerances) {
  CuqdynConf *cuqdyn_conf = malloc(sizeof(CuqdynConf));
  cuqdyn_conf->tolerances = tolerances;
  return cuqdyn_conf;
}

void destroy_cuqdyn_conf() {
  if (config == NULL) {
    return;
  }

  // TODO: This frees causes a double free error somehow
  // destroy_tolerances(config->tolerances);
  // free(config);
  config = NULL;
}

CuqdynConf *init_cuqdyn_conf_from_file(const char *filename) {
  CuqdynConf *tmp_config = malloc(sizeof(CuqdynConf));
  if (tmp_config == NULL) {
    fprintf(stderr, "ERROR: Memory allocation failed in function "
                    "init_cuqdyn_conf_from_file()\n");
    exit(1);
  }

  int flag = parse_cuqdyn_conf(filename, tmp_config);

  if (flag != 0) {
    fprintf(stderr, "ERROR: Unable to parse cuqdyn config file \"%s\"\n",
            filename);
    exit(1);
  }

  config = tmp_config;
  return config;
}

int parse_cuqdyn_conf(const char *filename, CuqdynConf *config) {
  xmlDocPtr doc = xmlReadFile(filename, NULL, 0);
  if (!doc) {
    fprintf(stderr, "Error: could not load XML file: %s\n", filename);
    return -1;
  }

  xmlNodePtr root = xmlDocGetRootElement(doc);
  xmlNodePtr cur = root->children;

  realtype rtol = 1e-6;
  N_Vector atol = NULL;
  int odes_count = 0;
  char **odes = NULL;

  for (; cur; cur = cur->next) {
    if (cur->type != XML_ELEMENT_NODE)
      continue;

    if (!xmlStrcmp(cur->name, (const xmlChar *)"tolerances")) {
      xmlNodePtr tolNode = cur->children;
      for (; tolNode; tolNode = tolNode->next) {
        if (tolNode->type != XML_ELEMENT_NODE)
          continue;

        if (!xmlStrcmp(tolNode->name, (const xmlChar *)"rtol")) {
          xmlChar *key = xmlNodeGetContent(tolNode);
          rtol = atof((char *)key);
          xmlFree(key);
        } else if (!xmlStrcmp(tolNode->name, (const xmlChar *)"atol")) {
          xmlChar *key = xmlNodeGetContent(tolNode);
          char *key_str = (char *)key;

          // Primera pasada: contar elementos
          size_t count = 0;
          char *tmp1 = strdup(key_str);
          char *token = strtok(tmp1, ",");
          while (token) {
            count++;
            token = strtok(NULL, ",");
          }
          free(tmp1);

          atol = N_VNew_Serial(count, get_sun_context());
          if (!atol) {
            fprintf(stderr, "Error: failed to allocate atol N_Vector\n");
            xmlFree(key);
            xmlFreeDoc(doc);
            return -1;
          }

          // Segunda pasada: parsear los valores
          size_t i = 0;
          char *tmp2 = strdup(key_str);
          token = strtok(tmp2, ",");
          while (token && i < count) {
            NV_Ith_S(atol, i++) = atof(token);
            token = strtok(NULL, ",");
          }
          free(tmp2);
          xmlFree(key);
        }
      }
    } else if (!xmlStrcmp(cur->name, (const xmlChar *)"odes")) {
      xmlChar *count_attr = xmlGetProp(cur, (const xmlChar *)"count");
      if (count_attr == NULL) {
        fprintf(stderr,
                "Error: <odes> node does not have a 'count' attribute\n");
        xmlFreeDoc(doc);
        return 1;
      }

      odes_count = atoi((char *)count_attr);
      xmlFree(count_attr);

      xmlChar *content = xmlNodeGetContent(cur);
      if (content == NULL) {
        fprintf(stderr, "Error: no content in <odes> node\n");
        xmlFreeDoc(doc);
        return 1;
      }

      char *odes_str = (char *)content;

      char *token = strtok(odes_str, "\n");

      odes = calloc(odes_count, sizeof(char *));

      int index = 0;
      while (token != NULL) {
        while (*token == ' ')
          token++;

        if (*token != '\0') {
          odes[index] = token;
          index++;
        }
        token = strtok(NULL, "\n");
      }
    }
  }

  config->tolerances = create_tolerances(rtol, atol, odes_count, odes);
  xmlFreeDoc(doc);
  return 0;
}

CuqdynConf *init_cuqdyn_conf(Tolerances tolerances) {
  destroy_cuqdyn_conf();

  config = create_cuqdyn_conf(tolerances);
  return config;
}

CuqdynConf *get_cuqdyn_conf() {
  if (config == NULL) {
    fprintf(stderr, "ERROR: cuqdyn config not initialized. Call "
                    "init_cuqdyn_conf_from_file() first.\n");
    exit(1);
  }

  return config;
}

Tolerances create_tolerances(realtype scalar_rtol, N_Vector atol,
                             int odes_count, char **odes) {
  Tolerances tolerances;
  tolerances.rtol = scalar_rtol;
  tolerances.atol = atol;
  tolerances.odes_count = odes_count;
  tolerances.odes = odes;
  return tolerances;
}

void destroy_tolerances(Tolerances tolerances) { N_VDestroy(tolerances.atol); }
