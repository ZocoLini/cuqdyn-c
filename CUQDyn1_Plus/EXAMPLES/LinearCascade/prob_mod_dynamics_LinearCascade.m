function dy = prob_mod_dynamics_LinearCascade(~, y, p)
%PROB_MOD_DYNAMICS_LINEARCASCADE Two-state irreversible linear cascade.
%
%   x1' = -k1*x1
%   x2' =  k1*x1 - k2*x2

k1 = p(1);
k2 = p(2);

dy = zeros(2, 1, 'like', y);
dy(1) = -k1 * y(1);
dy(2) =  k1 * y(1) - k2 * y(2);

end
