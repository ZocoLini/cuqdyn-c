%% Generation of noisy data

function data_generation_log(dt,k,noise)

p = [0.1,100];

tspan=0:dt:100;

l = length(tspan);

options = odeset('RelTol',1e-12,'AbsTol',1e-12*ones(1,1));
[t,x]=ode15s(@(t,x) prob_mod_dynamics_log(t,x,p),tspan,10,options);

[rows,cols] = size(x);
noise_levels = mean(x,1)*noise;

x(2:end,:) = x(2:end,:) + randn(rows-1,cols).*noise_levels;

noisy_data = x;

data_matrix = [transpose(tspan),noisy_data];

filename = sprintf('Data_Logistic/logistic_data_homoc_noise_%.2f_size_%d_data_%d.mat', noise, l, k);

save(filename, 'data_matrix');