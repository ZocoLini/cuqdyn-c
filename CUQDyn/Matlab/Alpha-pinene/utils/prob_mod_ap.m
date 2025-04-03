function [J,g,R]=prob_mod_ap(x,texp,yexp)
[tout,yout] = ode15s(@prob_mod_dynamics_ap,texp,[100 0 0 0 0],[],x);
R=(yout-yexp);
R=reshape(R,numel(R),1);
J = sum(sum((yout-yexp).^2));
g=0;
return
