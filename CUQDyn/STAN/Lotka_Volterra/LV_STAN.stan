functions {
  real[] lotka_volterra(real t, real[] y, real[] params, real[] x_r, int[] x_i) {
    real dydt[2]; # Two species
    dydt[1] = y[1] * (params[1] - params[2] * y[2]); 
    dydt[2] = -y[2] * (params[3] - params[4] * y[1]);
    return dydt;
  }
}
data {
  int<lower=1> T;
  int<lower=1> n_wells;
  real y0[2]; 
  real z[T, 2, n_wells];
  real t0;
  real ts[T];
}
transformed data {
  real x_r[0];
  int x_i[0];
}
parameters {
  real<lower=0.001> params[4]; 
  real<lower=0> sigma[2];
}
model {
  params[1] ~ normal(0.5,0.1); 
  params[2] ~ normal(0.02,0.01); 
  params[3] ~ normal(0.5,0.1); 
  params[4] ~ normal(0.02,0.01); 
  sigma ~ lognormal(-1,1);
  for (w in 1:n_wells) {
    real y_hat[T, 2];
    y_hat = integrate_ode_rk45(lotka_volterra, y0, t0, ts, params, x_r, x_i);
    for (t in 1:T) {
      for (j in 1:2) {
        z[t, j, w] ~ normal(y_hat[t, j], sigma[j]);
      }
    }
  }
}
generated quantities {
  real y_pred[T, 2, n_wells];
  real z_pred[T, 2, n_wells];
  for (w in 1:n_wells) {
    real y_pred_well[T, 2];
    y_pred_well = integrate_ode_rk45(lotka_volterra, y0, t0, ts, params, x_r, x_i);
    for (t in 1:T) {
      for (j in 1:2) {
        y_pred[t, j, w] = y_pred_well[t, j];
        z_pred[t, j, w] = y_pred_well[t, j] + normal_rng(0, sigma[j]);
      }
    }
  }
}
