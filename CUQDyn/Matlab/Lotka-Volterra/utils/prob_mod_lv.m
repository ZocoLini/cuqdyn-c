function [J,g,R]=prob_mod_lv(x,texp,yexp)
[tout,yout] = ode15s(@prob_mod_dynamics_lv,texp,[10,5],odeset('RelTol',1e-6,'AbsTol',1e-6*ones(1,2)),x);
R=(yout-yexp);
R=reshape(R,numel(R),1);
J = sum(sum((yout-yexp).^2));
g=0;
return
