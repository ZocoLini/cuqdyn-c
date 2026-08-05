# SIR Method Notes

The SIR example observes the infected population `I` and treats susceptible
`S` and recovered `R` as unobserved after the initial condition. This matches a
common epidemic-data setting where incidence or prevalence is measured while
the remaining compartments must be inferred through the ODE dynamics.

The bundled data are synthetic with additive Gaussian noise set to 10% of the
mean reference infected trajectory. The scripts use `known_sigma` residual
scaling so that residuals, optimizer cost, and FIM covariance all use the same
measurement-error scale.

The bounds are deliberately broad but physically positive:
`beta` ranges from `0.0001` to `0.01`, and `gamma` ranges from `0.01` to `2.0`.
These ranges cover plausible transmission and recovery rates around the
synthetic truth while preventing nonphysical negative rates.

The FIM and HybridCov scripts use the same observed-state conformal bands for
`I`. For hidden `S` and `R`, the FIM script uses local Gaussian propagation from
the Gauss-Newton covariance, while the HybridCov script keeps the FIM marginal
scale and replaces the correlation structure with the LOO parameter
correlation. The SBC scripts are the preferred way to judge whether that
covariance choice improves hidden-state calibration for a given SIR setting.
