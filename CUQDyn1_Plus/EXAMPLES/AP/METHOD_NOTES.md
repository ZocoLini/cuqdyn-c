# AP Method Notes

The alpha-pinene example is a five-state compartment model fitted to the
experimental `AP_measurementData_1_4.csv` dataset. The maintained scripts use
states `x1`, `x2`, `x3`, and `x4` as observed states, while `x5` is treated as
unobserved after the initial condition.

The default run scripts use unweighted residuals because the experimental
dataset does not provide measurement standard deviations. This makes the
objective a direct least-squares fit in the measurement units. If AP synthetic
data are used instead, prefer `known_sigma` with one standard deviation per
observed state so that optimization and FIM covariance use the same error
model as the data generator.

The parameter bounds are broad, from `0.05 * true_parameters` to
`5.0 * true_parameters`, because the experimental fit is more weakly
constrained than the synthetic examples and the rates have different physical
scales. The initial guess is `0.8 * true_parameters`, which gives the global
optimizer a plausible starting region without making the example a local-only
fit.

Both `CUQDyn1_Plus` and `CUQDyn1_Plus_HybridCov` are useful here. The observed
states receive LOO conformal prediction bands. The hidden states receive
delta-method bands from either the FIM covariance or the HybridCov covariance.
Because AP has only nine time points, the LOO ensemble is small; HybridCov
should be interpreted as an empirical covariance variant rather than a
guaranteed improvement for this model.
