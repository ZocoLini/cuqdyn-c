%% CUQDyn1 with MEIGO for Alpha-pinene

clear mex;
clear all;
close all;

addpath '..\MEIGO64-master\MEIGO'
addpath 'utils'
addpath 'Data_AP'

dataDir = 'Data_AP';
resultDir = 'Results_AP_CUQDyn2';

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

media_matrix = NaN(m, nstate, m);

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
% change number of parallel workers depending on your machine
% parpool('local', 20);
parpool('local', 10);

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
resultFileName = sprintf('result_CUQDyn2_lv.mat');
resultPath = fullfile(resultDir, resultFileName);                   
save(resultPath);