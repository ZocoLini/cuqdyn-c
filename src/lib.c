//
// Created by borja on 03/04/25.
//

#include <math.h>
#include <string.h>

enum FunctionType
{
    LOTKA_VOLTERRA = 0,
    ALPHA_PINENE = 1,
    LOGISTIC = 2
};

struct Problem
{
    enum FunctionType function_type;
    double *lower_bounds;
    double *upper_bounds;
    double *parameters;
};

struct Problem create_problem(enum FunctionType function_type, double *lower_bounds, double *upper_bounds, double *parameters)
{
    struct Problem problem;
    problem.function_type = function_type;
    problem.lower_bounds = lower_bounds;
    problem.upper_bounds = upper_bounds;
    problem.parameters = parameters;
    return problem;
}


struct Options
{
    int max_iterations;
    double *log_var_index;
    int should_save;
    char solver[];
};

struct Options create_options(const int max_iterations, double *log_var_index, const int should_save, char solver[])
{
    struct Options options;
    options.max_iterations = max_iterations;
    options.log_var_index = log_var_index;
    options.should_save = should_save;
    strcpy(options.solver, solver);
    return options;
}

/* Original MATLAB code
 *
 * % Function to solve the ODE system and return the solution
 *     function solution = ODE_solve(initial_values,times,parameters)
 *         [T,Y] = ode45(@(t,y) alpha_pin_ode(t, y, parameters), times, initial_values);
 *         solution = [T,Y];
 *     end
 *
 *  Solves the ODE system using the ode45 solver
 *  The second argument of the ode45 function is variable
 *      - lotka_volterra_ode
 *      - alpha_pin_ode
 *      - logisticGrowth_comp
 */

/*
 * Solves the ODE system using the ode45 solver
 *
 * initial_values: data_matrix(1,2:end);
 * times: data_matrix(:,1);
 * parameters: Result from meigo ESS in the original code
 */
struct Matrix solve_ode(struct Vector initial_values, struct Vector times, struct Vector parameters)
{

}

struct Results
{
    struct Vector best;
};

struct Results meigo(struct Problem, struct Options, struct Vector t, struct Matrix x)
{
    // TODO: Calls MEIGO in the MATLAB code --> MEIGO(problem,opts,'ESS',texp,yexp);
}

/* Original MATLAB code
 * -- Alpha-pinene
 *
 *     function dy=prob_mod_dynamics_ap(t,y,p)
 *         dy=zeros(5,1); %Initialize the state variables
 *         dy(1)=-(p(1)+p(2))*y(1);
 *         dy(2)=p(1)*y(1);
 *         dy(3)=p(2)*y(1)-(p(3)+p(4))*y(3)+p(5)*y(5);
 *         dy(4)=p(3)*y(3);
 *         dy(5)=p(4)*y(3)-p(5)*y(5);
 *     return
 *
 * -- Logistic
 *
 *  % Define the logistic growth ODE
 *     function dy = prob_mod_dynamics_log(t, y, p)
 *         dy = p(1) * y * (1 - y / p(2));
 *     return
 *
 * -- Lotka-Volterra
 *
 * %Function of the dynamic system
 *     function dy=prob_mod_dynamics_lv(t,y,p)
 *         dy=zeros(2,1); %Initialize the state variables
 *         dy(1)= (p(1)-p(2) * y(2)) * y(1);
 *         dy(2)=-1 * (p(4) - p(3) * y(1)) * y(2);
 *     return
 */

/*
 * t is not being used in the original code
 * x is a vector (?)
 * optimal_parameters is a vector of predefined values --> p = [0.5,0.02,0.02,0.5]; % Optimal parameters
 */

void prob_mod_dynamics_ap(double* _t, double* x, double* optimal_parameters)
{

}

void prob_mod_dynamics_log(double* _t, double* x, double* optimal_parameters)
{

}

void prob_mod_dynamics_lv(double* _t, const double* x, const double* optimal_parameters)
{
    // TODO: Allocate memory for dy and return a pointer to it (Maybe use Matrix or create Vector as a wrapper for matrix(1,n))
    double dy[] = {0, 0};

    dy[0] = x[0] * (optimal_parameters[0] - optimal_parameters[1] * x[1]);
    dy[1] = -1 * (optimal_parameters[3] - optimal_parameters[2] * x[0]) * x[1];
}


