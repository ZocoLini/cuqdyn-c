noise_levels = [0, 0.01, 0.05, 0.10];

vect_dt = [1, 0.5, 0.25];

for noise=noise_levels
    for dt=vect_dt
        for k=1:50
            data_lotka_volterra_homoc_mult(dt,k,noise)
        end
    end
end
