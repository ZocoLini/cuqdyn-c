# LV Method Notes

The Lotka-Volterra example is the smallest nonlinear benchmark in the
repository. Prey is observed at all post-initial time points, while predator is
hidden after the initial condition. This creates a compact partially observed
setting where the hidden trajectory is dynamically coupled to the measured
state.

The bundled dataset is synthetic with additive Gaussian noise set to 10% of the
mean reference prey trajectory. The maintained scripts therefore use
`known_sigma` residual scaling. This is the statistically coherent choice for
this example because the same observation-error standard deviation is used for
data generation, parameter estimation, and FIM covariance estimation.

The parameter bounds are `0.2 * true_parameters` to `2.0 * true_parameters`.
These bounds are intentionally moderate: wide enough to test global search and
parameter coupling, but narrow enough to avoid unrelated predator-prey regimes
that are not represented by the bundled data.

The FIM script is the baseline Gaussian delta-method workflow for the hidden
predator state. The HybridCov script reuses the same conformal treatment for
observed prey and changes only the covariance used for hidden-state propagation.
The LV tutorial also runs the bootstrap workflow, making this the clearest
example for comparing FIM, HybridCov, and bootstrap trajectory bands side by
side.
