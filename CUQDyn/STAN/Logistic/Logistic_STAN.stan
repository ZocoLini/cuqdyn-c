functions {
  real[] logisticgrowth(real t,
                  real[] y,
                  real[] theta,
                  real[] x_r,
                  int[] x_i
                  ) {
    real dydt[x_i[1]];
    for (i in 1:x_i[1]){
      dydt[i] = theta[1] * y[i] * (1-y[i]/theta[2]);
    }
    return dydt;
  }
}
data {
  int<lower=1> T;
  int<lower=1> n_wells;
  real y0[n_wells];
  real z[T,n_wells];
  real t0;
  real ts[T];
}
transformed data {
  real x_r[0];
  int x_i[1];
  x_i[1] = n_wells;
}
parameters {
  real<lower=0> theta[2];
  real<lower=0> sigma;
}
model {
  real y_hat[T,n_wells];
  theta[1] ~ normal(0,10);
  theta[2] ~ normal(100,10);
  sigma ~ normal(0,10);
  
  y_hat = integrate_ode_rk45(logisticgrowth, y0, t0, ts, theta, x_r, x_i);
  for (t in 1:T) {
    for (i in 1:n_wells) {
      z[t,i] ~ normal(y_hat[t,i], sigma);
    }
  }
}
generated quantities{
  real y_pred[T,n_wells];
  real z_pred[T,n_wells];
  y_pred = integrate_ode_rk45(logisticgrowth, y0, t0, ts, theta, x_r, x_i );
  for (t in 1:T) {
    for(i in 1:n_wells){
      z_pred[t,i] = y_pred[t,i] + normal_rng(0,sigma);
    }
  }
}

