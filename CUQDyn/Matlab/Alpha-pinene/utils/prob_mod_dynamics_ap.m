%Function of the dynamic system
function dy=prob_mod_dynamics_ap(t,y,p)
dy=zeros(5,1); %Initialize the state variables
dy(1)=-(p(1)+p(2))*y(1);
dy(2)=p(1)*y(1);
dy(3)=p(2)*y(1)-(p(3)+p(4))*y(3)+p(5)*y(5);
dy(4)=p(3)*y(3);
dy(5)=p(4)*y(3)-p(5)*y(5);
return
