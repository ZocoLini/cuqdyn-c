%% Generation of noisy data

function data_generation_lotka_volterra(dt,k,noise)

p = [0.5,0.02,0.02,0.5];

tspan=0:dt:30;

l = length(tspan);

options = odeset('RelTol',1e-6,'AbsTol',1e-6*ones(1,2));
[t,x]=ode15s(@(t,x) prob_mod_dynamics_lv(t,x,p),tspan,[10,5],options);

[rows,cols] = size(x);
noise_levels = mean(x,1)*noise;

x(2:end,:) = x(2:end,:) + randn(rows-1,cols).*noise_levels;

noisy_data = x;

data_matrix = [transpose(tspan),noisy_data];

filename = sprintf('Data_LV/lotka_volterra_data_homoc_noise_%.2f_size_%d_data_%d.mat', noise, l, k);

save(filename, 'data_matrix');