# LinearCascade Method Notes

The LinearCascade examples are controlled known-truth diagnostics rather than
general-purpose biological examples. They are included to test whether
weighted least-squares fitting, FIM covariance, complex-step sensitivities, and
hidden-state delta-method propagation agree with independent analytic or
matrix-exponential reference calculations.

The two-state diagnostic observes only downstream state `x2`; upstream state
`x1` is hidden. The three-state diagnostic observes only downstream state `x3`;
upstream states `x1` and `x2` are hidden. This design intentionally tests the
hardest direction for latent-state uncertainty: hidden upstream dynamics must
be inferred indirectly from downstream measurements.

Both diagnostics generate synthetic noisy observations internally and use
`known_sigma` residual scaling. The sigma is computed from the reference
trajectory using the same convention as the synthetic-data helpers, so the
optimizer objective and FIM covariance are matched to the data-generation noise
model.

The parameter bounds are moderate for the two-state cascade
(`0.2 * true_parameters` to `3.0 * true_parameters`) and wider for the
three-state cascade (`0.15 * true_parameters` to `4.0 * true_parameters`).
The wider three-state bounds make the downstream-only case a stronger
identifiability and covariance stress test.

The diagnostics primarily exercise `CUQDyn1_Plus` with FIM covariance and then
compare its covariance and hidden-state standard deviations against independent
reference calculations. The LinearCascade3 SBC scripts additionally compare
FIM and HybridCov from shared fits and are useful for checking hidden-state
coverage behavior across repeated synthetic datasets.
