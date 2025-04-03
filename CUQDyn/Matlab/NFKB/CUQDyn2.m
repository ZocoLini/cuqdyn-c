%% CUQDyn2 with MEIGO for NFKB

clear mex;
clear all;
close all;

addpath '..\MEIGO64-master\MEIGO';
addpath 'utils'
addpath 'Data_NFKB'

dataDir = 'Data_NFKB';
resultDir = 'Results_NFKB_CUQDyn2';

% Dataset

fileName = sprintf('nfkb_pe_data_homoc_ns_0.05.mat');
dataPath = fullfile(dataDir, fileName);

% Loading data
load(dataPath);

initial_values = data_matrix(1,2:end); % Initial values
times = data_matrix(:,1);			   % Time points
full_data = data_matrix(:,2:end);	   % Full data

observed_data = zeros(size(full_data, 1), 6); 
for i = 1:size(full_data, 1)
    observed_data(i, :) = observables(full_data(i, :)); % Observed data
end

%True model

nstate = 15;
p = [0.5 0.2 0.1 1 0.1 5e-7 0 0.0004 0.5 ...
                 0.0001 0.00002 5e-7 0 0.0004 0.5 0.0003 ...
                 0.0025 0.1 0.0015 0.000025 0.000125 5 ...
                 0.0025 0.01 0.001 0.0005 5e-7 0 0.0004]; % Nominal parameters
n_pars = 29;

dt = 60;
tspan=[0:dt:3*3600];
               
options = odeset('RelTol',1e-12,'AbsTol',1e-12*ones(1,15));
[t_true,x_true]=ode15s(@(t,x) prob_mod_dynamics_NFKB_PE(t,x,p),tspan,initial_values,options);
times_true = t_true;
data_true = x_true;    

n = size(data_matrix,2)-1;
m = size(data_matrix,1);

init_pars = [0.5 0.2 0.1 1 0.1 0 0 0.0002 0.5 0.0001 0.00001 0 0 0.0003 0.5 0.0002 0.0022 0.1 0.0012 0.000022 0.0001 5 0.002 0.01 0.001 0.0003 0 0 0.0002];
nom_par_sc = [5 2 1 1 1 5 0 4 5 1 2 5 0 4 5 3 2.5 1 1.5 2.5 1.25 5 2.5 1 1 5 5 0 4];
pert_p=1.2*p;

% Initialization

problem.f='prob_mod_NFKB_PE_LS_res_scaled';                    
problem.x_L=zeros(1,n_pars); % Lower bounds of the variables
problem.x_U=6*ones(1,n_pars); % Upper bounds of the variables    
problem.x_0=pert_p; % Initial points
opts.maxeval=5e3; % Maximum number of function evaluations (default 1000)
opts.log_var=[1:n_pars]; % Indexes of the variables which will be analyzed using a logarithmic distribution instead of an uniform one
opts.local.solver='n2fb';
opts.inter_save=1; %  Saves results of intermediate iterations in eSS_report.mat
texp = times;
yexp = observed_data;
Results_tot=MEIGO(problem,opts,'ESS',texp,yexp);
parameters_init = Results_tot.xbest; % Optimal parameters
solution_tot = ODE_solve_NFKB_PE(initial_values,tspan,parameters_init);
media_tot = solution_tot(:, 2:end);

problem.x_0=parameters_init;
parpool('local', 20);
parfor i=2:m
    texp = times([1:i-1,i+1:end]);
    yexp = observed_data([1:i-1,i+1:end],:);
    Results=MEIGO(problem,opts,'ESS',texp,yexp);
    parameters = Results.xbest; % Optimal parameters
    solution = ODE_solve_NFKB_PE(initial_values,times,parameters);                    
    media = solution(:, 2:end);
    tr_media = zeros(size(media, 1), 6);
    for j = 1:(size(media, 1))
        tr_media(j, :) = observables(media(j, :));
    end
    resid_loo(i,:) = abs(observed_data(i,:) - tr_media(i,:)); % Residuals                    
    media_matrix(:,:,i) = tr_media;
end
delete(gcp('nocreate'));

% Predicted model (full data)
h_yout = zeros(size(media_tot, 1), 6);
for i = 1:(size(media_tot, 1))
    h_yout(i, :) = observables(media_tot(i, :));
end

%True model
h_xtrue = zeros(size(tspan, 2), 6);
for i = 1:(size(tspan, 2))
    h_xtrue(i, :) = observables(x_true(i, :));
end

%Transformed initial values
tr_init_val = transpose(observables(initial_values));

%Regions
alp=0.05;
cf=1-alp;

for i=1:size(resid_loo,2)
    sigma(i)=sqrt(sum(resid_loo(:,i).^2)/n);
    st_resid(:,i) = resid_loo(:,i)/sigma(i);
end

vect_quant = st_resid(:);
quant = quantile(vect_quant,cf);
                
regionsi = NaN(m,size(resid_loo,2));
regionss = NaN(m,size(resid_loo,2));

regionsi(1,:) = tr_init_val;
regionss(1,:) = tr_init_val;

for i=2:m
	for j=1:size(media_matrix,2)
		med_vect(i-1,j) = median(media_matrix(i,j,2:end));
    end
end

for i=2:m
    for j=1:size(media_matrix,2)
        regionsi(i,j) = med_vect(i-1,j)-quant*sigma(j);
        regionss(i,j) = med_vect(i-1,j)+quant*sigma(j);
    end
end

% Store the results
resultFileName = sprintf('result_CUQDyn2_NFKB.mat');
resultPath = fullfile(resultDir, resultFileName);                    
save(resultPath);