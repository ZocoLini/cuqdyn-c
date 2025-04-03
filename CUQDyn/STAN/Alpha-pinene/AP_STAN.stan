functions {
  real[] alpha_pinene_isomerization(real t, real[] y, real[] params, real[] x_r, int[] x_i) {
    real dydt[5]; # Five equations
    dydt[1] = -(params[1] + params[2]) * y[1]; 
    dydt[2] = params[1] * y[1]; 
    dydt[3] = params[2] * y[1] - (params[3] + params[4]) * y[3] + params[5] * y[5];
    dydt[4] = params[3] * y[3];
    dydt[5] = params[4] * y[3] - params[5] * y[5];
    return dydt;
  }
}

data {
  int<lower=1> T;
  int<lower=1> n_wells;
  real y0[5];
  real<lower=0> z[T, 5, n_wells];
  real t0;
  real ts[T];
}

transformed data {
  real x_r[0];
  int x_i[0];
}

parameters {
  real<lower=0> params[5];
  real<lower=0> sigma[5]; 
}

model {
  params[1] ~ normal(0, 0.001);
  params[2] ~ normal(0, 0.001);
  params[3] ~ normal(0, 0.001);
  params[4] ~ normal(0, 0.001);
  params[5] ~ normal(0, 0.001);
  sigma ~ lognormal(-1, 1); 
  for (w in 1:n_wells) {
    real y_hat[T, 5];
    y_hat = integrate_ode_rk45(alpha_pinene_isomerization, y0, t0, ts, params, x_r, x_i);
    for (t in 1:T) {
      for (j in 1:5) {
        z[t, j, w] ~ normal(y_hat[t, j], sigma[j]);
      }
    }
  }
}

generated quantities {
  real y_pred[T, 5, n_wells];
  real z_pred[T, 5, n_wells];
  for (w in 1:n_wells) {
    real y_pred_well[T, 5];
    y_pred_well = integrate_ode_rk45(alpha_pinene_isomerization, y0, t0, ts, params, x_r, x_i);
    for (t in 1:T) {
      for (j in 1:5) {
        y_pred[t, j, w] = y_pred_well[t, j];
        z_pred[t, j, w] = y_pred_well[t, j] + normal_rng(0, sigma[j]);
      }
    }
  }
}
