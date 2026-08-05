# NFKB Method Notes

The NF-kB example is the largest maintained benchmark, with 15 states and 29
parameters. The synthetic dataset observes 10 selected states after the initial
condition and leaves the remaining states hidden. This gives a higher
dimensional partially observed problem than LV, SIR, or AP.

The bundled dataset is synthetic with additive Gaussian noise set to 5% of the
mean reference trajectory for each observed state. The maintained FIM and
HybridCov scripts use `known_sigma` residual scaling, with one scale per
observed state, so states with different magnitudes contribute on a comparable
measurement-error scale.

The parameter bounds are `0.1 * true_parameters` to `4.0 * true_parameters`.
These bounds preserve positive kinetic rates while giving MEIGO enough room to
move in the high-dimensional parameter space. The initial guess is
`0.8 * true_parameters`, which keeps the example computationally manageable
without turning it into a purely local refinement.

The FIM script is the baseline for hidden-state Gaussian propagation. The
HybridCov script is especially relevant in this example because many parameters
are coupled through partially observed dynamics. The legacy `run_NFKB_example.m`
is retained only as a diagnostic runner; new comparisons should use
`run_NFKB_example_CUQDyn1plus.m` and
`run_NFKB_example_CUQDyn1plus_HybCov.m`.

NF-kB is also the maintained stress test for identifiability diagnostics. Before
interpreting hidden-state bands or parameter intervals, inspect
`results.diagnostics.fim` for the FIM parameterization, rank, condition number,
and weak-direction count, and inspect `results.diagnostics.fim_reliability` or
the `FIMReliability` sheet written by `diagnose_uq_quality`. Bands marked as
affected by weak FIM directions should be reported as unreliable rather than as
ordinary calibrated prediction intervals.
