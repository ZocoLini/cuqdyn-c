//
// Created by borja on 03/04/25.
//

#include <math.h>

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
void solve_ode(struct Matrix initial_values, struct Matrix times, struct Matrix parameters)
{

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


