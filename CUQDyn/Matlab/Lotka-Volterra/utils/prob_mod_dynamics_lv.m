%Function of the dynamic system
function dy=prob_mod_dynamics_lv(t,y,p)
dy=zeros(2,1); %Initialize the state variables
dy(1)=(p(1)-p(2)*y(2))*y(1);
dy(2)=(p(3)*y(1)-p(4))*y(2);
return
