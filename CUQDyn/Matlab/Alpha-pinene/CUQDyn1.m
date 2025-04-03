%% CUQDyn1 with MEIGO for Alpha-pinene

clear mex;
clear all;
close all;

addpath '..\MEIGO64-master\MEIGO'
addpath 'utils'
addpath 'Data_AP'

dataDir = 'Data_AP';
resultDir = 'Results_AP_CUQDyn1';

% Dataset

fileName = sprintf('measurementData.csv');
dataPath = fullfile(dataDir, fileName);
data_matrix = readmatrix('measurementData.csv');

initial_values = data_matrix(1,2:end); % Initial values
times = data_matrix(:,1);			   % Time points
observed_data = data_matrix(:,2:end);  % Observed data    

n = size(data_matrix,2)-1;  % Number of observables
m = size(data_matrix,1);    % Number of time points

nstate = 5; % Number of states

alp = 0.05; %Predictive region level

media_matrix = NaN(sz, nstate, sz);

% Initialization

problem.f='prob_mod_ap';                    
problem.x_L=zeros(1,n); % Lower bounds of the variables
problem.x_U=ones(1,n); % Upper bounds of the variables    
problem.x_0=ones(1,n); % Initial points
opts.maxeval=3e3; % Maximum number of function evaluations (default 1000)
opts.log_var=[1:n]; % Indexes of the variables which will be analyzed using a logarithmic distribution instead of an uniform one
opts.local.solver='nl2sol'; % Local solver to perform the local search
opts.inter_save=1; %  Saves results of intermediate iterations in eSS_report.mat
texp = times;
yexp = observed_data;
Results_tot=MEIGO(problem,opts,'ESS',texp,yexp);
parameters_init = Results_tot.xbest; % Optimal parameters
solution_tot = ODE_solve(initial_values,times,parameters_init);
media_tot = solution_tot(:, 2:end);

problem.x_0=parameters_init;
parpool('local', 20);

parfor i=2:m                    
	texp = times([1:i-1,i+1:end]);
    yexp = observed_data([1:i-1,i+1:end],:);                    
    Results=MEIGO(problem,opts,'ESS',texp,yexp);
    parameters = Results.xbest; % Optimal parameters
    solution = ODE_solve(initial_values,times,parameters);                    
    media = solution(:, 2:end); 
    resid_loo(i,:) = abs(observed_data(i,:) - media(i,:)); % Residuals                    
    media_matrix(:,:,i) = media;
end

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
resultFileName = sprintf('result_CUQDyn1_lv.mat');
resultPath = fullfile(resultDir, resultFileName);                   
save(resultPath);