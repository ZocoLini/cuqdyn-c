/*
 * TCP cost server: lets MATLAB's MEIGO optimise using the REAL C cost.
 *
 * This is the C half of the hybrid experiment: both pipelines share the same
 * optimiser (MATLAB's MEIGO, same seed) and the same integrator family
 * (CVODES); the only difference is who evaluates the cost - MATLAB code or
 * this server, which uses the exported cuqdyn-c primitives (solve_ode +
 * cuqdyn_residual_weight), i.e. the exact code path the CLI optimises with.
 *
 *   ./cost_server <cuqdyn_config.xml> <data_file> <port>
 *
 * Protocol, line-based, one client at a time:
 *   client:  "p1 p2 ... pn\n"          (n = p_count parameters)
 *   server:  "J r1 r2 ... rk\n"        (cost + k = m*n_obs weighted residuals,
 *                                       column-major over observed states,
 *                                       matching MATLAB's R(:) flattening)
 *   client:  "quit\n"                   -> server exits 0
 * If the ODE solve fails for a theta, the server replies "nan\n" and the
 * MATLAB side maps it to a large penalty, mirroring what a failed integration
 * costs the optimiser there.
 */

#include <arpa/inet.h>
#include <math.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "config.h"
#include "cuqdyn.h"
#include "data_reader.h"
#include "functions.h"
#include "ode_solver.h"

int main(int argc, char *argv[])
{
    if (argc < 4)
    {
        fprintf(stderr, "Usage: %s <cuqdyn_config.xml> <data_file> <port>\n", argv[0]);
        return 2;
    }

    if (init_cuqdyn_context_from_file(argv[1]) == NULL)
    {
        fprintf(stderr, "ERROR: cannot read cuqdyn config %s\n", argv[1]);
        return 2;
    }
    const CuqdynConf *conf = get_cuqdyn_conf(get_cuqdyn_context());

    CuqdynData data;
    if (read_data_file(argv[2], &data) != 0)
    {
        fprintf(stderr, "ERROR: cannot read data file %s\n", argv[2]);
        return 2;
    }

    const long n_params = conf->ode_expr.p_count;
    const long m = NV_LENGTH_S(data.times);
    const sunrealtype t0 = NV_Ith_S(data.times, 0);
    N_Vector theta = New_Serial(n_params);

    const int port = atoi(argv[3]);
    const int listener = socket(AF_INET, SOCK_STREAM, 0);
    const int reuse = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons((unsigned short) port);

    if (bind(listener, (struct sockaddr *) &addr, sizeof(addr)) != 0 || listen(listener, 1) != 0)
    {
        fprintf(stderr, "ERROR: cannot listen on port %d\n", port);
        return 2;
    }
    fprintf(stdout, "cost_server: listening on %d (%ld params, %ld times, %d observed)\n", port, n_params, m,
            data.n_obs);
    fflush(stdout);

    for (;;)
    {
        const int client = accept(listener, NULL, NULL);
        if (client < 0)
        {
            continue;
        }
        FILE *in = fdopen(client, "r");
        FILE *out = fdopen(dup(client), "w");
        setvbuf(out, NULL, _IOLBF, 0);

        char line[8192];
        long served = 0;
        while (fgets(line, sizeof(line), in) != NULL)
        {
            if (strncmp(line, "quit", 4) == 0)
            {
                fclose(in);
                fclose(out);
                fprintf(stdout, "cost_server: served %ld evaluations, quitting\n", served);
                destroy_cuqdyn_data(&data);
                return 0;
            }

            char *cursor = line;
            int ok = 1;
            for (long p = 0; p < n_params; ++p)
            {
                char *end;
                NV_Ith_S(theta, p) = strtod(cursor, &end);
                if (end == cursor)
                {
                    ok = 0;
                    break;
                }
                cursor = end;
            }
            if (!ok)
            {
                fprintf(out, "nan\n");
                continue;
            }

            TransposedStates states = solve_ode(theta, data.initial_values, t0, data.times);
            if (states == NULL)
            {
                fprintf(out, "nan\n");
                continue;
            }

            /* Weighted residuals, flattened column-major over observed states
             * exactly like MATLAB's R(:) in prob_mod_cost_LV. Compute first,
             * then emit the whole reply as one line. */
            double *residuals = malloc((size_t) m * data.n_obs * sizeof(double));
            double j_total = 0.0;
            long idx = 0;
            for (int j = 0; j < data.n_obs; ++j)
            {
                const long state = data.observed_idx[j];
                const double w = cuqdyn_residual_weight(&conf->cost, j);
                for (long i = 0; i < m; ++i)
                {
                    const double r = (SM_ELEMENT_D(states, state, i) - SM_ELEMENT_D(data.observed_data, j, i)) * w;
                    residuals[idx++] = r;
                    j_total += r * r;
                }
            }
            fprintf(out, "%.17g", j_total);
            for (long k = 0; k < idx; ++k)
            {
                fprintf(out, " %.17g", residuals[k]);
            }
            fprintf(out, "\n");
            free(residuals);
            SUNMatDestroy(states);
            served++;
        }
        fclose(in);
        fclose(out);
    }
}
