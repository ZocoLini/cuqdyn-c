%% CUQDyn1 with MEIGO for Logistic Model

clear mex;
clear all;
close all;

addpath '..\MEIGO64-master\MEIGO'
addpath 'utils'
addpath 'Data_Logistic'

dataDir = 'Data_Logistic';
resultDir = 'Results_Logistic_CUQDyn1';

% Dataset

ns = 0.10;  %Noise level
sz = 10;	%Size of the dataset
ks = 1;		%Label of the dataset

fileName = sprintf('logistic_data_homoc_noise_%.2f_size_%d_data_%d.mat', ns, sz, ks);
dataPath = fullfile(dataDir, fileName);

% Loading data
load(dataPath);

initial_values = data_matrix(1,2:end); % Initial values
times = data_matrix(:,1);			   % Time points
observed_data = data_matrix(:,2:end);  % Observed data   

n = size(data_matrix,2)-1; % Number of observables
m = size(data_matrix,1);   % Number of time points

%True model

nstate = 1;		% Number of states
p = [0.1, 100]; % Optimal parameters
               
dt = 5;
tspan=[0:dt:100];

% tolerances for integration of ODEs 
% options = odeset('RelTol',1e-12,'AbsTol',1e-12*ones(1,1));
options = odeset('RelTol',1e-6,'AbsTol',1e-6*ones(1,1));

% true model trajectories
[t_true,x_true]=ode15s(@(t,x) prob_mod_dynamics_log(t,x,p),tspan,10,options);
times_true = t_true;
data_true = x_true; 

alp = 0.05; %Predictive region level

media_matrix = NaN(m, nstate, m);

% Initialization

problem.f='prob_mod_log';                    
problem.x_L=zeros(1,2); % Lower bounds of the variables
problem.x_U=[1 200]; % Upper bounds of the variables
problem.x_0=[0.5 150]; % Initial points
opts.maxeval=3e3; % Maximum number of function evaluations (default 1000)
opts.log_var=[1:n]; % Indexes of the variables which will be analyzed using a logarithmic distribution instead of an uniform one
opts.local.solver='nl2sol'; % Local solver to perform the local search
opts.inter_save=1; %  Saves results of intermediate iterations in eSS_report.mat
texp = times;
yexp = observed_data;
Results_tot=MEIGO(problem,opts,'ESS',texp,yexp);
parameters_init = Results_tot.xbest; % Optimal parameters
solution_tot = ODE_solve_log(initial_values,times,parameters_init);
media_tot = solution_tot(:, 2:end);
   
problem.x_0=parameters_init;
% change number of parallel workers depending on your machine
% parpool('local', 20);
parpool('local', 10);

parfor i=2:m                    
    texp = times([1:i-1,i+1:end]);
    yexp = observed_data([1:i-1,i+1:end],:);                    
    Results=MEIGO(problem,opts,'ESS',texp,yexp);
    parameters = Results.xbest; % Optimal parameters
    solution = ODE_solve_log(initial_values,times,parameters);                    
    media = solution(:, 2:end); 
    resid_loo(i,:) = abs(observed_data(i,:) - media(i,:)); % Residuals                    
    media_matrix(:,:,i) = media;
end

delete(gcp('nocreate'));

cf = 1-alp;
for j=1:n
	q_low(1,:) = initial_values;
    q_up(1,:) = initial_values;
    for i=2:m
		for k=1:(m-1)
			m_low(i,j,k) = media_matrix(i,j,k+1)-resid_loo(k+1,j);
            m_up(i,j,k) = media_matrix(i,j,k+1)+resid_loo(k+1,j);
        end
        q_low(i,j) = quantile(m_low(i,j,:),alp);
        q_up(i,j) = quantile(m_up(i,j,:),1-alp);
    end
end    
% Define the upper and lower regions
regionsi = q_low;
regionss = q_up;

%Store the results
resultFileName = sprintf('result_CUQDyn1_logistic_noise_%.2f_size_%d_k_%d_alpha_%.2f.mat', ns, sz, ks, cf);
resultPath = fullfile(resultDir, resultFileName);
save(resultPath);

