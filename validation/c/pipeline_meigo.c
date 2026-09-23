/*
 * Layer 5: the C pipeline driven by MATLAB's MEIGO.
 *
 * This file defines execute_ess_solver(), the one function through which
 * cuqdyn_algo() reaches the optimiser. libcuqdyn-c.a is a static library whose
 * ess_solver.o defines nothing else and is referenced only by cuqdyn.o, so
 * linking this object first replaces the sacess-based optimiser with the one
 * below and leaves every other line of the pipeline untouched. The CLI's own
 * sources are compiled into the same binary (see validation/CMakeLists.txt),
 * so what runs is the CLI itself with its optimiser swapped.
 *
 * The optimiser is MATLAB's MEIGO, reached over one TCP connection. For each
 * launch k (0 = full fit, then the m-1 leave-one-out refits in order) this side
 * sends "optimize", serves every "eval" with the library's real objective
 * (obj_func) and returns the vector MATLAB reports in "done". All randomness
 * lives in MATLAB, seeded per launch with base_seed + k on both sides.
 *
 *   C -> M   optimize k n_params m_fit
 *   M -> C   eval p1 ... pn
 *   C -> M   J r1 ... rK              (K = n_obs * m_fit, column-major over observed states)
 *   M -> C   done p1 ... pn J
 *   C -> M   quit                     (after launch m-1)
 *
 * Environment:
 *   CUQDYN_MEIGO_PORT            port to listen on (default 45602)
 *   CUQDYN_MEIGO_TRACE_DIR       where to write evals_<k>.txt and theta_<k>.txt
 *   CUQDYN_MEIGO_LOOPBACK_THETA  "p1 p2 ... pn": no socket, every launch returns
 *                                this vector after CUQDYN_MEIGO_LOOPBACK_EVALS
 *                                (default 3) evaluations of it - a plumbing test
 *
 * initial_params is ignored: both pipelines start every launch from the
 * problem guess (CUQDyn1_Plus semantics).
 */

#include <arpa/inet.h>
#include <errno.h>
#include <method_module/structure_paralleltestbed.h>
#include <netinet/in.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sunmatrix/sunmatrix_dense.h>
#include <sys/socket.h>
#include <unistd.h>

#include "config.h"
#include "cuqdyn.h"
#include "ess_solver.h"
#include "functions.h"
#include "textio.h"

static FILE *g_in = NULL;
static FILE *g_out = NULL;
static long g_launch = -1;
static long g_launches_total = -1;

/* Every message is a string literal, so the prefix concatenates at compile
 * time; exit() is what tells the analyser nothing runs after a die(). */
#define die(...)                                                                                                       \
    do                                                                                                                 \
    {                                                                                                                  \
        fprintf(stderr, "pipeline_meigo: " __VA_ARGS__);                                                               \
        fprintf(stderr, "\n");                                                                                         \
        exit(2);                                                                                                       \
    } while (0)

static long env_long(const char *name, long fallback)
{
    const char *s = getenv(name);
    long v;
    if (s == NULL || *s == '\0')
    {
        return fallback;
    }
    if (!parse_long(s, &v))
    {
        die("%s is not an integer: %s", name, s);
    }
    return v;
}

/* Parses up to n whitespace-separated doubles from s; returns how many. */
static long parse_doubles(const char *s, double *out, long n)
{
    long count = 0;
    const char *cursor = s;
    while (count < n)
    {
        char *end = NULL;
        const double v = strtod(cursor, &end);
        if (end == cursor)
        {
            break;
        }
        out[count++] = v;
        cursor = end;
    }
    return count;
}

static void listen_and_accept(void)
{
    const long port = env_long("CUQDYN_MEIGO_PORT", 45602);
    if (port < 1 || port > 65535)
    {
        die("CUQDYN_MEIGO_PORT out of range: %ld", port);
    }
    const int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0)
    {
        die("socket: %s", strerror(errno));
    }
    const int reuse = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons((unsigned short) port);
    if (bind(listener, (struct sockaddr *) &addr, sizeof(addr)) != 0 || listen(listener, 1) != 0)
    {
        die("cannot listen on 127.0.0.1:%ld: %s", port, strerror(errno));
    }
    fprintf(stdout, "pipeline_meigo: waiting for MATLAB on 127.0.0.1:%ld\n", port);
    fflush(stdout);
    const int client = accept(listener, NULL, NULL);
    if (client < 0)
    {
        die("accept: %s", strerror(errno));
    }
    close(listener);
    const int client_out = dup(client);
    g_in = fdopen(client, "r");
    g_out = client_out < 0 ? NULL : fdopen(client_out, "w");
    if (g_in == NULL || g_out == NULL)
    {
        die("cannot wrap the MATLAB socket in streams");
    }
    setvbuf(g_out, NULL, _IOFBF, 1 << 16);
}

static FILE *open_trace(const char *what, long k)
{
    const char *dir = getenv("CUQDYN_MEIGO_TRACE_DIR");
    if (dir == NULL || *dir == '\0')
    {
        return NULL;
    }
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s_%ld.txt", dir, what, k);
    FILE *f = fopen(path, "w");
    if (f == NULL)
    {
        die("cannot write %s", path);
    }
    return f;
}

static void trace_row(FILE *f, const double *theta, long n, double j)
{
    if (f == NULL)
    {
        return;
    }
    for (long i = 0; i < n; ++i)
    {
        fprintf(f, "%.17g ", theta[i]);
    }
    fprintf(f, "%.17g\n", j);
}

/* The library's objective, exactly as sacess calls it. Returns J; *residuals
 * (owned by the caller) gets the K weighted residuals. */
static double evaluate(experiment_total *exp, double *x, double **residuals, long *n_residuals)
{
    output_function *res = obj_func(x, exp);
    const double j = res->value;
    *n_residuals = res->size_r;
    *residuals = res->R;
    free(res->J);
    free(res);
    return j;
}

N_Vector execute_ess_solver(const char *config_file, const char *output, N_Vector texp, SUNMatrix yexp,
                            N_Vector initial_condition, N_Vector initial_params, int *observed_idx)
{
    (void) config_file;
    (void) output;
    (void) initial_params;

    const CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());
    const long n_params = conf->ode_expr.p_count;
    if (n_params < 1)
    {
        die("p_count must be positive, got %ld", n_params);
    }
    if (conf->time_scaling != 1.0)
    {
        die("time_scaling=%g is not supported by layer 5", conf->time_scaling);
    }

    g_launch++;
    const long k = g_launch;
    const long m_fit = SM_COLUMNS_D(yexp);
    if (k == 0)
    {
        g_launches_total = m_fit; /* the full fit plus m-1 refits */
    }

    experiment_total exp;
    memset(&exp, 0, sizeof(exp));
    exp.texp = texp;
    exp.yexp = yexp;
    exp.initial_values = initial_condition;
    exp.observed_idx = observed_idx;

    N_Vector theta = New_Serial(n_params);
    double *x = malloc((size_t) n_params * sizeof(double));
    FILE *evals = open_trace("evals", k);
    double j_final = 0.0;

    const char *loopback = getenv("CUQDYN_MEIGO_LOOPBACK_THETA");
    if (loopback != NULL && *loopback != '\0')
    {
        if (parse_doubles(loopback, x, n_params) != n_params)
        {
            die("CUQDYN_MEIGO_LOOPBACK_THETA needs %ld numbers", n_params);
        }
        const long evals_per_launch = env_long("CUQDYN_MEIGO_LOOPBACK_EVALS", 3);
        for (long e = 0; e < evals_per_launch; ++e)
        {
            double *r = NULL;
            long n_r = 0;
            j_final = evaluate(&exp, x, &r, &n_r);
            free(r);
            trace_row(evals, x, n_params, j_final);
        }
    }
    else
    {
        if (g_out == NULL)
        {
            listen_and_accept();
        }
        fprintf(g_out, "optimize %ld %ld %ld\n", k, n_params, m_fit);
        fflush(g_out);

        char line[8192];
        int done = 0;
        while (!done)
        {
            if (fgets(line, sizeof(line), g_in) == NULL)
            {
                die("MATLAB closed the connection during launch %ld", k);
            }
            if (strncmp(line, "eval ", 5) == 0)
            {
                if (parse_doubles(line + 5, x, n_params) != n_params)
                {
                    die("eval line with fewer than %ld numbers", n_params);
                }
                double *r = NULL;
                long n_r = 0;
                const double j = evaluate(&exp, x, &r, &n_r);
                fprintf(g_out, "%.17g", j);
                for (long i = 0; i < n_r; ++i)
                {
                    fprintf(g_out, " %.17g", r[i]);
                }
                fprintf(g_out, "\n");
                fflush(g_out);
                free(r);
                trace_row(evals, x, n_params, j);
            }
            else if (strncmp(line, "done ", 5) == 0)
            {
                double *values = malloc((size_t) (n_params + 1) * sizeof(double));
                if (parse_doubles(line + 5, values, n_params + 1) != n_params + 1)
                {
                    die("done line with fewer than %ld numbers", n_params + 1);
                }
                memcpy(x, values, (size_t) n_params * sizeof(double));
                j_final = values[n_params];
                free(values);
                done = 1;
            }
            else
            {
                die("unexpected line from MATLAB: %s", line);
            }
        }
        if (k == g_launches_total - 1)
        {
            fprintf(g_out, "quit\n");
            fflush(g_out);
            fclose(g_out);
            fclose(g_in);
            g_out = NULL;
            g_in = NULL;
        }
    }

    if (evals != NULL)
    {
        fclose(evals);
    }
    FILE *final = open_trace("theta", k);
    trace_row(final, x, n_params, j_final);
    if (final != NULL)
    {
        fclose(final);
    }
    for (long i = 0; i < n_params; ++i)
    {
        NV_Ith_S(theta, i) = x[i];
    }
    free(x);
    fprintf(stdout, "pipeline_meigo: launch %ld done, J=%.10g\n", k, j_final);
    fflush(stdout);
    return theta;
}
