# Bayesian ABC-SMC Comparison Scripts

This folder contains PyMC ABC-SMC scripts used as Bayesian posterior-predictive
comparisons for the CUQDyn1_Plus examples. The relevant maintained examples are:

| Model | MATLAB wrapper | Python script | Shared data CSV |
|---|---|---|---|
| Lotka-Volterra | `run_bayes_lv.m` | `lv_pymc.py` | `../EXAMPLES/LV/data/lv2_synthetic_data_noi10_partobs_1.csv` |
| SIR | `run_bayes_sir.m` | `sir_pymc.py` | `../EXAMPLES/SIR/data/sir_data.csv` |
| Alpha-pinene | `run_bayes_ap.m` | `ap_pymc.py` | `../EXAMPLES/AP/data/AP_measurementData_1_4.csv` |
| NF-kB | `run_bayes_nfkb.m` | `nfkb_pymc.py` | `../EXAMPLES/NFKB/data/NFKB_synthetic_data_5n_36st_partobs10.csv` |

Run these scripts from this folder. The MATLAB wrappers call the Python scripts
with `uv run python ...`, then read the exported CSVs and generate MATLAB plots.

```matlab
cd pymc_matlab
run_bayes_lv
run_bayes_sir
run_bayes_ap
run_bayes_nfkb
```

Or run the Python scripts directly:

```bash
cd pymc_matlab
uv run python lv_pymc.py
uv run python sir_pymc.py
uv run python ap_pymc.py
uv run python nfkb_pymc.py
```

The scripts write outputs under `results/<model>/`, including posterior samples,
mean trajectories, per-state trajectory ensembles, and posterior-predictive
plots. Observed-state `*_trajectories.csv` files include an additive
observation-noise term estimated from the posterior-mean RMSE, so they are the
right exports for observed-data coverage comparisons. The corresponding
`*_latent_trajectories.csv` files keep parameter-uncertainty-only trajectories.
Hidden-state `*_trajectories.csv` files are latent trajectories, because no
observation-noise model is available for hidden states. The `results/` directory
is ignored by Git.

Current comparison settings use 500 exported trajectory samples for every
state. SIR, AP, and NF-kB use 1000 ABC-SMC draws per chain; LV uses 4000 draws
per chain. AP priors match the current CUQDyn AP bounds (`0.05x` to `5.0x`
nominal parameters). NF-kB can be rerun with a different draw count by setting
the `NFKB_PYMC_DRAWS` environment variable before running `nfkb_pymc.py`; it
can also write to an alternate folder through `NFKB_PYMC_RESULTS_DIR`.

## CUQDyn-vs-PyMC Comparison Summaries

After running the PyMC workflows and the corresponding CUQDyn examples, use:

```matlab
cd pymc_matlab
compare_cuqdyn_pymc
```

This script does not rerun inference. It reads the existing PyMC CSV exports in
`results/<model>/` and the latest CUQDyn result folders in `../EXAMPLES/<model>/`.
It then writes a timestamped comparison folder under `results/comparison/` with:

- `parameter_summary_comparison.csv` and `.xlsx`, using one common schema for
  PyMC posterior samples, CUQDyn FIM, and CUQDyn HybridCov parameter estimates.
- `trajectory_band_summary_comparison.csv` and `.xlsx`, with per-state band
  widths, observed-state coverage where observations exist, and observed-state
  RMSE.
- `<model>_cuqdyn_vs_pymc*.png`, `.fig`, `.pdf`, and `.eps` overlay plots
  showing PyMC predictive bands beside CUQDyn uncertainty bands.

The comparison layer currently covers LV, SIR, AP, and NF-kB. It intentionally
uses completed outputs rather than changing the underlying CUQDyn or PyMC
inference scripts. The PyMC observed-state bands are computed from the
noise-augmented exported trajectory ensembles; hidden-state bands remain latent
posterior trajectory bands.

## Environment

The project includes `pyproject.toml` and `uv.lock`, so the simplest setup is:

```bash
cd pymc_matlab
uv sync
```

The main dependencies are PyMC, ArviZ, NumPy, SciPy, pandas, and matplotlib.
On Windows, see `pyMC_windows_install.md` for the full setup, including `uv`,
VS Code Python support, MSYS2, and the UCRT64 GCC/G++ toolchain used by
PyTensor.

## Data Alignment

These Bayesian scripts intentionally read the same CSV files used by the
corresponding CUQDyn MATLAB examples. If a synthetic dataset is regenerated,
regenerate it through the canonical generator in `EXAMPLES/<model>/data_generation/`
so both CUQDyn and PyMC continue to use the same observations.
