//
// Created by borja on 03/04/25.
//

#include <cvode/cvode.h>
#include <lib.h>
#include <math.h>
#include <nvector/nvector_serial.h>
#include <stdio.h>
#include <string.h>
#include <sundials/sundials_context.h>
#include <sundials/sundials_matrix.h>
#include <sundials/sundials_nvector.h>

static SUNMatrix calc_media(Problem problem, Options options, N_Vector texp, SUNMatrix yexp,
                            N_Vector initial_values, N_Vector times);

void solve_lotka_volterra()
{
    int retval; // TODO: Handle the error. See cvRoberts_dns.c for example inside cvode src
    SUNContext sunctx;

    retval = SUNContext_Create(SUN_COMM_NULL, &sunctx);


    const char dataDir[] = "Data_LV";
    const char resultDir[] = "Results_LV_CUQDyn1";

    const double noise_lvl = 0.10;
    const int data_size = 31; // TODO: We need this as a function parameter or extracted from the file
    const int data_label = 1;

    // data filename of the original MATLAB code TODO: This should be a function parameter
    char format[] = "lotka_volterra_data_homoc_noise_%.2f_size_%d_data_%d.mat";
    char filename[strlen(format) - 3 + 1];
    sprintf(filename, format, noise_lvl, data_size, data_label);
    char datapath[strlen(filename) + strlen(dataDir) + 2];
    sprintf(datapath, "%s/%s", dataDir, filename);

    /* Original MATLAB code - % Load data and dataset
     * load(datapath); % creates the variable data_matrix (?)
     *
     * % Accedemos a la primera fila y copiamos los valores desde la segunda columna hasta el final -> Vector
     * initial_values = data_matrix(1,2:end); % Initial values
     *
     * % De todas las filas, accedemos a la primera columna y copiamos los valores -> Vector
     * times = data_matrix(:,1);			   % Time points
     *
     * % De todas las filas, copiamos los valores desde la segunda columna hasta el final -> Matriz
     * observed_data = data_matrix(:,2:end);  % Observed data -> Matrix
     */

    // Loaded previously and returned from load.
    // Original implementation returned a data_matrix and created the variables.
    // We will obtain the variables directly from the specified file

    N_Vector initial_values = N_VNew_Serial(0, sunctx);
    N_Vector times = N_VNew_Serial(0, sunctx);
    SUNMatrix observed_data = SUNDenseMatrix(0, 0, sunctx);

    /* Original MATLAB code
     * n = size(data_matrix,2) - 1;  % Number of observables - columns - 1
     * m = size(data_matrix,1);    % Number of time points - rows
     */

    int n = NV_LENGTH_S(initial_values);
    int m = NV_LENGTH_S(times);

    /* Orignal MATLAB code - % True model
     * NOTE: This doens't look to be neccesary in the C implementation
     *
     * nstate = 2;
     * p = [0.5,0.02,0.02,0.5]; % Optimal parameters
     * n_par = length(p);
     *
     * dt = 0.01;
     * tspan=[0:dt:30];
     *
     * options = odeset('RelTol',1e-12,'AbsTol',1e-12*ones(1,nstate));
     * [t_true,x_true]=ode15s(@(t,x) prob_mod_dynamics_lv(t,x,p),tspan,[10,5],options);
     * times_true = t_true;
     * data_true = x_true;
     */

    /* Original MATLAB code
     * nstate = 2; % Number of states
     * alp = 0.05; %Predictive region level NOTE: This is used
     * media_matrix = NaN(sz, nstate, sz);
     */

    // NOTE: This looks like something that we should receive as a parameter
    const int number_of_states = 2; // No se que carajos es esto
    const double alp = 0.05; // Predictive region level

    Matrix3D media_matrix = create_matrix3d(data_size, number_of_states, data_size);

    /* Original MATLAB code
     * % Initialization
     *
     *     % Object problem
     *     problem.f='prob_mod_lv';
     *     problem.x_L=0.001*ones(1,4); % Lower bounds of the variables
     *     problem.x_U=ones(1,4); % Upper bounds of the variables
     *     problem.x_0=[0.3, 0.3, 0.3, 0.3]; % Initial points
     *
     *     % Object options
     *     opts.maxeval=3e3; % Maximum number of function evaluations (default 1000)
     *     opts.log_var=[1:4]; % Indexes of the variables which will be analyzed using a logarithmic distribution
     * instead of an uniform one opts.local.solver='nl2sol'; % Local solver to perform the local search
     * opts.inter_save=1; %  Saves results of intermediate iterations in eSS_report.mat %opts.plot=1; texp = times; yexp
     * = observed_data;
     *
     *     % Call to MEIGO
     *     Results_tot=MEIGO(problem,opts,'ESS',texp,yexp);
     *     parameters_init = Results_tot.xbest; % Optimal parameters
     *     solution_tot = ODE_solve_LV(initial_values,times,parameters_init);
     *     media_tot = solution_tot(:, 2:end); % NOTE: This look unused
     *
     *     problem.x_0=parameters_init;
     */

    // TODO: This both problem and options should be passed as parameters
    Problem problem = create_problem(LOTKA_VOLTERRA, NULL, NULL, NULL);
    const Options options = create_options(3000, NULL, 0, "nl2sol");

    N_Vector texp = times;
    SUNMatrix yexp = observed_data;

    const Results results_tot = meigo(problem, options, texp, yexp);
    N_Vector parameters_init = results_tot.best; // Optimal parameters
    problem.parameters = parameters_init;

    /* Original MATLAB code
     *     parfor i=2:m
     *         texp = times([1:i-1,i+1:end]);
     *         yexp = observed_data([1:i-1,i+1:end],:);
     *         Results=MEIGO(problem,opts,'ESS',texp,yexp);
     *         parameters = Results.xbest; % Optimal parameters
     *         solution = ODE_solve_LV(initial_values,times,parameters);
     *         media = solution(:, 2:end);
     *         resid_loo(i,:) = abs(observed_data(i,:) - media(i,:)); % Residuals
     *         media_matrix(:,:,i) = media;
     *     end
     */

    // Starting from one because the first one is already done to assign parameters_init
    for (int i = 1; i < m; ++i)
    {
        texp;
        yexp;

        SUNMatrix media = calc_media(problem, options, texp, yexp, initial_values, times);

        // resid_loo
        // media_matrix
    }
}

/* This function encapsulates the following MATLAB logic:
 *
 *     Results=MEIGO(problem,opts,'ESS',texp,yexp);
 *     parameters = Results.xbest; % Optimal parameters
 *     solution = ODE_solve_LV(initial_values,times,parameters);
 *     media = solution(:, 2:end);
 *
 * The original function, despite being called "media", it takes the result of the ODE solver
 * and returns it without the first column, which I guess is the time.
 */
static SUNMatrix calc_media(Problem problem, Options options, N_Vector texp, SUNMatrix yexp,
                            N_Vector initial_values, N_Vector times)
{
    Results results = meigo(problem, options, texp, yexp);
    N_Vector parameters = results.best; // Optimal parameters
    SUNMatrix solution = solve_ode(initial_values, times, parameters);
    SUNMatrix media; // TODO: Remove first column of solutions

    return media;
}
