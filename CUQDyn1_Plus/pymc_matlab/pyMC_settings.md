# PyMC ABC-SMC Settings

This file documents the PyMC settings used by the Bayesian comparison scripts
in this folder. The MATLAB wrappers call these Python scripts with
`uv run python <script>.py`; the Python scripts read the same CSV files used by
the corresponding CUQDyn examples.

## Common Settings

- Inference method: PyMC `pm.Simulator` with `pm.sample_smc`.
- Chains: 4 for all models.
- Inference RNG seed: 42 for ABC-SMC sampling.
- Posterior trajectory export: 500 posterior draws selected by
  `pymc_export_utils.posterior_indices`.
- Export RNG seed: 42 for posterior draw selection.
- Observed-state trajectory exports include additive Gaussian observation noise
  with `sigma` estimated as the RMSE between the posterior-mean trajectory and
  the observed data. Hidden-state exports remain latent parameter-uncertainty
  trajectories.
- Optional Windows PyTensor compile cache override:
  `set PYTENSOR_FLAGS=base_compiledir=%TEMP%\pytensor_cache` before running
  PyMC, or use another writable local cache folder.
- Plot backend: Matplotlib `Agg`.

## Summary Table

| Problem | Script | Data CSV | Priors | ABC distance / normalization | Epsilon | Draws per chain | SMC thresholds | ODE tolerances in simulator |
|---|---|---|---|---|---:|---:|---|---|
| Lotka-Volterra | `lv_pymc.py` | `../EXAMPLES/LV/data/lv2_synthetic_data_noi10_partobs_1.csv` | Uniform: `alpha [0.10, 1.00]`, `beta [0.004, 0.04]`, `delta [0.004, 0.04]`, `gamma [0.10, 1.00]` | Default PyMC Simulator ABC distance on observed prey `y1` | 3 | 4000 | `threshold=0.6`, `correlation_threshold=0.01` | `rtol=1e-5`, `atol=1e-7` |
| SIR | `sir_pymc.py` | `../EXAMPLES/SIR/data/sir_data.csv` | Uniform: `beta [1e-4, 1e-2]`, `gamma [0.01, 2.0]` | Default PyMC Simulator ABC distance on observed infected state `y2` | 20 | 1000 | `threshold=0.3`, `correlation_threshold=0.1` | `rtol=1e-5`, `atol=1e-7` |
| Alpha-pinene | `ap_pymc.py` | `../EXAMPLES/AP/data/AP_measurementData_1_4.csv` | Uniform bounds equal nominal values times `[0.05, 5.0]`: `p1 [2.965e-06, 2.965e-04]`, `p2 [1.480e-06, 1.480e-04]`, `p3 [1.025e-06, 1.025e-04]`, `p4 [1.375e-05, 1.375e-03]`, `p5 [2.000e-06, 2.000e-04]` | Default PyMC Simulator ABC distance on `y1-y4` after dividing each observed state by its time mean | 0.5 | 1000 | `threshold=0.5`, `correlation_threshold=0.1` | `rtol=1e-4`, `atol=1e-8` |
| NF-kB | `nfkb_pymc.py` | `../EXAMPLES/NFKB/data/NFKB_synthetic_data_5n_36st_partobs10.csv` | Uniform bounds equal CUQDyn support: `0.1 * TRUE_PARAMS` to `4.0 * TRUE_PARAMS` for each of 29 parameters | Custom normalized L1 distance over observed states `y1,y2,y3,y5,y7,y9,y11,y12,y13,y15`; each observed state is divided by its observed maximum | 1.0 | 1000 | `threshold=0.3`, `correlation_threshold=0.1` | `rtol=1e-5`, `atol=1e-7` |

## Lotka-Volterra

- Observed state: prey, `y1`.
- Hidden state: predator, `y2`.
- Initial condition: all states from the first CSV row.
- True parameters used for plotting/comparison:
  `alpha=0.5`, `beta=0.02`, `delta=0.02`, `gamma=0.5`.
- Priors match the CUQDyn bounds `true * [0.2, 2.0]`.
- Posterior mean trajectory is recomputed with tighter tolerances:
  `rtol=1e-8`, `atol=1e-10`.
- Exported trajectories:
  `prey_trajectories.csv` is noise-augmented;
  `prey_latent_trajectories.csv` and `predator_trajectories.csv` are latent.

## SIR

- Observed state: infected, `y2`.
- Hidden states: susceptible `y1` and recovered `y3`.
- Initial condition: all states from the first CSV row.
- True parameters used for plotting/comparison: `beta=0.002`, `gamma=0.5`.
- Priors match the CUQDyn bounds `beta [0.0001, 0.01]` and
  `gamma [0.01, 2.0]`.
- Posterior mean trajectory is recomputed with tighter tolerances:
  `rtol=1e-8`, `atol=1e-10`.
- Exported trajectories:
  `infected_trajectories.csv` is noise-augmented;
  `infected_latent_trajectories.csv`, `susceptible_trajectories.csv`, and
  `recovered_trajectories.csv` are latent.

## Alpha-pinene

- Observed states: `y1-y4`.
- Hidden state: `y5` after `t=0`.
- Initial condition: all states from the first CSV row.
- Nominal parameters used for bounds and plotting:
  `[5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05]`.
- Observed states are divided by their time means before flattening into the
  ABC observed vector, so the four observed states contribute on comparable
  scales.
- Posterior mean trajectory is recomputed with tighter tolerances:
  `rtol=1e-8`, `atol=1e-10`.
- Exported observed-state trajectories `y1_trajectories.csv` through
  `y4_trajectories.csv` are noise-augmented. `y5_trajectories.csv` is latent.
  Each state also has a `*_latent_trajectories.csv` export.

## NF-kB

- Observed states: `y1`, `y2`, `y3`, `y5`, `y7`, `y9`, `y11`, `y12`, `y13`,
  and `y15`.
- Hidden states: `y4`, `y6`, `y8`, `y10`, and `y14`.
- Initial condition: all states from the first CSV row.
- Parameters: 29 kinetic parameters `p1-p29`.
- Priors are independent Uniform distributions over the CUQDyn parameter
  support, from `0.1 * TRUE_PARAMS` to `4.0 * TRUE_PARAMS`.
- The default draw count is 1000 per chain. Set `NFKB_PYMC_DRAWS=4000` (or
  another integer) before running the script to perform a convergence-sensitivity
  rerun without editing the file.
- The default output folder is `results/nfkb`. Set `NFKB_PYMC_RESULTS_DIR` to
  keep alternate draw-count runs separate from the comparison baseline.
- The custom distance returns `-dist / epsilon`, where `dist` is the sum of
  absolute normalized residuals over all observed states and times.
- Posterior mean trajectory is exported with `rtol=1e-6`, `atol=1e-8`.
- Exported observed-state trajectories are noise-augmented; hidden-state
  trajectories are latent. Every state also has a `*_latent_trajectories.csv`
  export.

## Diagnostics

All four scripts print ArviZ `r_hat` and `ess_bulk` diagnostics for the inferred
parameters and flag `r_hat > 1.01` or `ess_bulk < 100 * chains`. LV, SIR, and AP
also print observed-state posterior-predictive coverage for the noise-augmented
95% interval and flag coverage below 85%.

The NF-kB script additionally prints `post_mean/true` ratios and warns when the
posterior remains close to the broad Uniform prior mean for many parameters.
That warning is a weak-identifiability/prior-dominance diagnostic; passing the
R-hat/ESS gate does not by itself make NF-kB parameter recovery trustworthy.
