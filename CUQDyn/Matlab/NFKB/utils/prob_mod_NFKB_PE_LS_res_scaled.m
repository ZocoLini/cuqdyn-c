function [J,g,R]=prob_mod_NFKB_PE_LS_res_scaled(x,texp,yexp)
cond_inic = [0.2  0 0 0 0  3.155e-004 2.2958e-003 ...
            4.78285e-003 2.8697e-006 2.50663e-003 ...
            3.43573e-003 2.86971e-006 0.06 ...
            7.888e-005 2.86971e-006];
options = odeset('RelTol',1e-8,'AbsTol',1e-8*ones(1,15));
[tout,yout] = ode15s(@prob_mod_dynamics_NFKB_PE,texp,cond_inic,options,x);

h_yout = zeros(size(yout, 1), 6);
for i = 1:size(yout, 1)
    h_yout(i, :) = observables(yout(i, :));
end

state_means = mean(yexp);

R = (yexp - h_yout) ./ state_means;
R=reshape(R,numel(R),1);
J = sum(sum((yexp-h_yout).^2));
g=0;
return