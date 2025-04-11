%% Generation of noisy data

function data_generation_NFKB_PE(tspan)

p = [0.5 0.2 0.1 1 0.1 5e-7 0 0.0004 0.5 ...
                 0.0001 0.00002 5e-7 0 0.0004 0.5 0.0003 ...
                 0.0025 0.1 0.0015 0.000025 0.000125 5 ...
                 0.0025 0.01 0.001 0.0005 5e-7 0 0.0004];

init_cond = [0.2  0 0 0 0  3.155e-004 2.2958e-003 ...
            4.78285e-003 2.8697e-006 2.50663e-003...
            3.43573e-003 2.86971e-006 0.06 ...
            7.888e-005 2.86971e-006];

options = odeset('RelTol',1e-8,'AbsTol',1e-8*ones(1,15));
[t,x]=ode15s(@(t,x) prob_mod_dynamics_NFKB_PE(t,x,p),tspan,init_cond,options);

noise = 0.05;

[rows,cols] = size(x);
noise_levels = mean(x,1)*noise;

x(2:end,:) = x(2:end,:) + randn(rows-1,cols).*noise_levels;

noisy_data = x;

data_matrix = [transpose(tspan),noisy_data];

save('Data_NFKB/nfkb_pe_data_homoc_ns_0.05.mat', 'data_matrix');