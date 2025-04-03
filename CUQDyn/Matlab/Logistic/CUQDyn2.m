%% CUQDyn2 with MEIGO for Logistic model

clear mex;
clear all;
close all;

addpath '..\MEIGO64-master\MEIGO';
addpath 'utils'
addpath 'Data_Logistic'

dataDir = 'Data_Logistic';
resultDir = 'Results_Logistic_CUQDyn2';

% Dataset

ns = 0.10;  %Noise level
sz = 11;	%Size of the dataset
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
               
options = odeset('RelTol',1e-12,'AbsTol',1e-12*ones(1,1));
[t_true,x_true]=ode15s(@(t,x) prob_mod_dynamics_log(t,x,p),tspan,10,options);
times_true = t_true;
data_true = x_true;

alp = 0.05; %Predictive region level
 
media_matrix = NaN(sz, nstate, sz);

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
parpool('local', 20);

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
                
for i=1:n
	sigma(i)=sqrt(sum(resid_loo(:,i).^2)/n);
    st_resid(:,i) = resid_loo(:,i)/sigma(i);
end
                                
vect_quant = st_resid(:);
quant = quantile(vect_quant,cf);
               
regionsi = NaN(m,n);
regionss = NaN(m,n);

regionsi(1,:) = initial_values;
regionss(1,:) = initial_values;
               
for i=2:m
	for j=1:n
		med_vect(i-1,j) = median(media_matrix(i,j,2:end));
    end
end

for i=2:m
	for j=1:n
		regionsi(i,j) = med_vect(i-1,j)-quant*sigma(j);
        regionss(i,j) = med_vect(i-1,j)+quant*sigma(j);
    end
end
                
%Store the results
resultFileName = sprintf('result_CUQDyn2_noise_%.2f_size_%d_k_%d_alpha_%.2f.mat', ns, sz, ks, cf);
resultPath = fullfile(resultDir, resultFileName); 
save(resultPath);