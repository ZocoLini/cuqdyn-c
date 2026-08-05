function J = jacobianest_cs(f, x0)
% Complex-step Jacobian estimator (h = 1e-20).
% Callable only from functions in src/ (MATLAB private convention).
h  = 1e-20;
n  = numel(x0);
x0 = x0(:);
f0 = f(x0);
J  = zeros(numel(f0), n);
for k = 1:n
    xp     = x0;
    xp(k)  = xp(k) + 1i * h;
    J(:,k) = imag(f(xp)) / h;
end
end
