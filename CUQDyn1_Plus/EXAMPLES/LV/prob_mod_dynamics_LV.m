% Function of the dynamic system
% Simple Lotka-Volterra model with 2 species
function dy=prob_mod_dynamics_LV(t,y,p)
dy=zeros(2,1,'like',y); %Initialize the state variables
dy(1)=(p(1)-p(2)*y(2))*y(1);
dy(2)=(p(3)*y(1)-p(4))*y(2);
return
