functions {
  real[] nfkb_pe(real t, real[] y, real[] params, real[] x_r, int[] x_i) {
    real dydt[15];
    dydt[1] = params[20]-params[21]*y[1]-params[17]*y[1]; 
    dydt[2] = params[17]*y[1]-params[19]*y[2]-params[18]*y[2]*y[8]-params[21]*y[2]-params[2]*y[2]*y[10]+params[3]*y[4]-params[4]*y[2]*y[13]+params[5]*y[5];
    dydt[3] = params[19]*y[2]+params[18]*y[2]*y[8]-params[21]*y[3];
    dydt[4] = params[2]*y[2]*y[10]-params[3]*y[4];
    dydt[5] = params[4]*y[2]*y[13]-params[5]*y[5];
    dydt[6] = params[11]*y[13]-params[1]*y[6]*y[10]+params[5]*y[5]-params[23]*y[6];
    dydt[7] = params[23]*params[22]*y[6]-params[1]*params[11]*y[7];
    dydt[8] = params[15]*y[9]-params[16]*y[8];
    dydt[9] = params[13]+params[12]*y[7]-params[14]*y[9];
    dydt[10] = -params[2]*y[2]*y[10]-params[1]*y[10]*y[6]+params[9]*y[12]-params[10]*y[10]-params[25]*y[10]+params[26]*y[11];
    dydt[11] = -params[1]*y[11]*y[7]+params[25]*params[22]*y[10]-params[26]*params[22]*y[11];
    dydt[12] = params[7]+params[6]*y[7]-params[8]*y[12];
    dydt[13] = params[1]*y[10]*y[6]-params[11]*y[13]-params[4]*y[2]*y[13]+params[24]*y[14];
    dydt[14] = params[1]*y[11]*y[7]-params[24]*params[22]*y[14];
    dydt[15] = params[28]+params[27]*y[7]-params[29]*y[15];
    return dydt;
  }
  
  real[] observables(real[] y) {
    real h[6];
    h[1] = y[7];
    h[2] = y[10] + y[13];
    h[3] = y[9];
    h[4] = y[1] + y[2] + y[3];
    h[5] = y[2];
    h[6] = y[12];
    return h;
  }
}
data {
  int<lower=1> T;
  int<lower=1> n_wells;
  real y0[15];
  real z[T, 6, n_wells]; # Six observables
  real t0;
  real ts[T];
}
transformed data {
  real x_r[0];
  int x_i[0];
}
parameters {
  real<lower=0.001> params[29];
  real<lower=0> sigma[6];
}
model {
  params[1] ~ normal(0.6,0.2);
  params[2] ~ normal(0.24,0.08);
  params[3] ~ normal(0.12,0.04);
  params[4] ~ normal(1.2,0.4);
  params[5] ~ normal(0.12,0.04);
  params[6] ~ normal(6e-7,2e-7);
  params[7] ~ normal(0,0.002);
  params[8] ~ normal(0.00048,1.6e-4);
  params[9] ~ normal(0.6,0.2);
  params[10] ~ normal(0.00012,4e-5);
  params[11] ~ normal(2.4e-5,8e-6);
  params[12] ~ normal(6e-7,2e-7);
  params[13] ~ normal(0,0.002);
  params[14] ~ normal(0.00048,1.6e-4);
  params[15] ~ normal(0.6,0.2);
  params[16] ~ normal(0.00036,1.2e-4);
  params[17] ~ normal(0.003,0.001);
  params[18] ~ normal(0.12,0.04);
  params[19] ~ normal(0.0018,0.0006);
  params[20] ~ normal(3e-5,1e-5);
  params[21] ~ normal(0.00015,5e-5);
  params[22] ~ normal(6,2);
  params[23] ~ normal(0.003,0.001);
  params[24] ~ normal(0.012,0.004);
  params[25] ~ normal(0.0012,0.0004);
  params[26] ~ normal(0.0006,0.0002);
  params[27] ~ normal(6e-7,2e-7);
  params[28] ~ normal(0,0.002);
  params[29] ~ normal(0.00048,1.6e-4);
  sigma ~ lognormal(-1,1);
  for (w in 1:n_wells) {
    real y_hat[T, 15];
    real h_y_hat[T, 6];
    y_hat = integrate_ode_bdf(nfkb_pe, y0, t0, ts, params, x_r, x_i);
    for (t in 1:T) {
      h_y_hat[t] = observables(y_hat[t]);
      for (j in 1:6) {
        z[t, j, w] ~ normal(h_y_hat[t, j], sigma[j]);
      }
    }
  }
}
generated quantities {
  real y_pred[T, 15, n_wells];
  real z_pred[T, 6, n_wells];
  for (w in 1:n_wells) {
    real y_pred_well[T, 15];
    real h_y_pred_well[T, 6];
    y_pred_well = integrate_ode_bdf(nfkb_pe, y0, t0, ts, params, x_r, x_i);
    for (t in 1:T) {
      h_y_pred_well[t] = observables(y_pred_well[t]);
      for (j in 1:6) {
        y_pred[t, j, w] = h_y_pred_well[t, j];
        z_pred[t, j, w] = h_y_pred_well[t, j] + normal_rng(0, sigma[j]);
      }
    }
  }
}

