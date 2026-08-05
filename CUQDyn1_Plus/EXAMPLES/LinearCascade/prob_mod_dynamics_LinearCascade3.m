function dy = prob_mod_dynamics_LinearCascade3(~, y, p)
%PROB_MOD_DYNAMICS_LINEARCASCADE3 Three-state irreversible linear cascade.
%
%   x1' = -k1*x1
%   x2' =  k1*x1 - k2*x2
%   x3' =  k2*x2 - k3*x3

k1 = p(1);
k2 = p(2);
k3 = p(3);

dy = zeros(3, 1, 'like', y);
dy(1) = -k1 * y(1);
dy(2) =  k1 * y(1) - k2 * y(2);
dy(3) =  k2 * y(2) - k3 * y(3);

end
