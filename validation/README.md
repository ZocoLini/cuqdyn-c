# Validating the C port against the MATLAB reference

The C/Rust code in this repository is a transpilation of the MATLAB in
`CUQDyn1_Plus/` and `CUQDyn/`. This directory checks that the transpilation
is faithful. **Current status: every deterministic layer is green** — 79/79
kernel checks and 71/71 pipeline checks across the 4 models of the preprint
(Lotka-Volterra, alpha-pinene, SIR and NF-kB).

## Why a naive end-to-end comparison does not work

The obvious validation — run the CLI, run `CUQDyn1_Plus.m`, diff the bands —
fails, because eSS is a stochastic global optimiser: two runs of the *same*
implementation with different seeds already produce different parameters and
different bands. In a direct MATLAB-vs-C diff, optimiser noise buries any
real transpilation bug.

The fix is to compare in layers, removing the noise wherever possible.
Each layer freezes everything the previous one could not:

| Layer | Name | What is actually done | A failure means | Optimiser noise | Status |
|---|---|---|---|---|---|
| 1 | **Algebra kernels** | MATLAB's pure-math functions (`cuqdyn_fim_covariance`, the hybrid covariance, `cuqdyn_residual_variance`, `quantile`) were run once on fixed synthetic inputs and their inputs+outputs frozen in `golden/`. `test_golden.c` re-runs the C counterparts (`fim.c`, `matlab.c`) on the same inputs and diffs the outputs. | a transpilation bug in the linear algebra | none | ✅ **79/79** |
| 2 | **Integration & sensitivities** | MATLAB integrates each model with `ode15s` at the TRUE parameters and derives dy/dθ by complex step (exact); both are frozen in `baseline/matlab/<m>/layer2/`. `test_baseline.c` integrates the same ODE with CVODES, computes CVODES forward sensitivities, and diffs trajectory and each dy/dθ_k block. | wrong RHS (e.g. parameter order), integrator config, or broken sensitivities | none | ✅ 4/4 models |
| 3 | **UQ replay** | One seeded full MATLAB run per model; its fitted θ̂, the entire LOO ensemble (per-refit trajectories, held-out residuals, refit parameters) and the resulting bands are frozen in `baseline/matlab/<m>/layer3/`. `test_baseline.c` **injects** θ̂ and the ensemble into the C band code (`conformal_bands()`, `delta_method_bands()`) and diffs bands, `Cov_p` and `std_y` against MATLAB's. Identical inputs → the optimiser is out of the equation. | a bug in the band mathematics (conformal quantiles, FIM covariance, delta propagation) | none | ✅ 4/4 models |
| 4 | **Statistical end-to-end** | Each side runs the FULL pipeline N times with different seeds (MATLAB: `gen_baseline(model, 4, 1:N)`; C: `run_c_seeds.sh model N`). `compare_baseline.py` compares the *distributions*: per-parameter median/IQR, band-width ratios per state, empirical coverage of the true trajectory. This is the only layer that exercises the eSS interface itself. | a systematic bias in the optimiser coupling — or nothing: two correct implementations still differ run to run | dominant (it is what is measured) | tooling ready, campaign running |

Key results of layers 2-3 (details and tolerances in `baseline/README.md`):

- **Conformal bands: machine-exact** on all 4 models.
- Trajectories and sensitivities agree to 1e-7..1e-4 (two correct
  integrators at rtol 1e-6).
- Delta-method bands of hidden states: 1e-5 (2.9% on NF-kB, consistent with
  its cond(FIM) ~ 3e8).
- End-to-end with matched budgets: parameters agree to 0.01-1.7% on
  LV2/SIR/AP; on NF-kB they spread because of the problem's own
  non-identifiability, not the code.

## What is stored in each directory

```
validation/
├── gen_golden.m       MATLAB script that (re)generates golden/
├── test_golden.c      C comparator for layer 1 (the validation_golden ctest)
├── golden/            LAYER-1 REFERENCE DATA ("golden vectors").
│                      One folder per test case (fim_01_small_log, hyb_01_plain,
│                      var_01_estimated, qnt_01...). Each folder holds the plain-text
│                      INPUTS fed to the MATLAB kernel (J.txt, theta.txt, opts.txt...)
│                      and the OUTPUTS MATLAB produced for them (expect_*.txt).
│                      test_golden.c re-runs the C kernels on the same inputs and
│                      compares against expect_*. If a check fails, the C algebra
│                      diverged from MATLAB on that exact input.
│
└── baseline/          LAYERS 2-4 MATERIAL, one level up in realism.
    ├── gen_baseline.m       MATLAB generator (seeded, sequential) of matlab/<model>/
    ├── test_baseline.c      C comparator for layers 2+3 (the baseline_* ctests)
    ├── matlab/<model>/      THE MATLAB REFERENCE per model (lv2, ap, sir, nfkb),
    │   │                    all plain text so no one needs MATLAB to consume it:
    │   ├── layer2/          trajectory + complex-step sensitivities at the TRUE
    │   │                    parameters (traj.txt, sens.txt, theta_fixed.txt).
    │   │                    No optimiser involved at all.
    │   ├── layer3/          one seeded CUQDyn1_Plus run: fitted parameters
    │   │                    (theta_hat.txt), the whole LOO ensemble
    │   │                    (loo_params.txt, media_matrix.txt, resid_loo.txt),
    │   │                    the bands (q_low/q_up.txt), cov_p.txt, std_y.txt.
    │   │                    test_baseline.c injects these into the C band code
    │   │                    and compares its output against the MATLAB bands.
    │   └── times/y0/truth/sigma/meta/tol.txt   shared context + the comparison
    │                        tolerances (editable without regenerating anything)
    ├── c_<model>_seed1_results.txt   reference C runs (full pipeline,
    │                        SACESS_SEED=1) the figures were rendered from
    ├── matlab_<model>_hybrid_uq_plot.png / c_<model>_seed1_hybrid_uq_plot.png
    │                        the side-by-side band figures, one pair per model
    ├── plot_c_results_matlab_style.py   renders any cuqdyn-results.txt like MATLAB
    ├── ap_partobs_*         the AP partially-observed example (data + configs);
    │                        lives here until promoted to example-files/
    ├── nfkb_cuqdyn_fullsigma.xml   NF-kB config with full-precision sigmas
    ├── nfkb_ess_serial_2e4.xml     NF-kB eSS config with the MATLAB-matched budget
    ├── run_c_seeds.sh / compare_baseline.py / drago_baseline.sbatch   layer-4
    │                        tooling: N seeded C runs, distribution report, SLURM
    └── write_expected_output.m   generates the reference tests/test_cuqdyn_algo.c
                             can compare against (files land outside validation/)
```

In one sentence each: **`golden/` = frozen inputs+outputs of the MATLAB
algebra kernels; `baseline/matlab/` = frozen trajectories, ensembles and bands
of full seeded MATLAB runs.** Everything else is the machinery to generate
them (MATLAB side) or compare against them (C side).

## Running the validation

The only build prerequisite: the top-level `CMakeLists.txt` does not register
this directory yet; add one line after `add_subdirectory(tests)`:

```cmake
add_subdirectory(validation)
```

Then build and test as usual (on CESGA, first
`module load cesga/2025 gcc/13.4.0 openmpi/5.0.7 rust/1.88.0` — the default
system cargo is from 2020 and cannot build the crate):

```bash
mkdir -p build-serial && cd build-serial
cmake -DCMAKE_TOOLCHAIN_FILE=../toolchains/serial_toolchain.cmake ..
make -j 8
ctest -R "validation_golden|baseline" --output-on-failure
```

- `validation_golden` — layer 1. A failure = a transpilation bug in the
  algebra.
- `baseline_lv2` / `baseline_ap` / `baseline_sir` / `baseline_nfkb` — layers
  2+3 per model. They report SKIP when the MATLAB exports are absent (they
  are included in this branch, so they should actually run).

For the per-check table, run the binaries directly:

```bash
./build-serial/validation/test_golden validation/golden 1e-9
./build-serial/validation/baseline/test_baseline validation/baseline/matlab/lv2 \
    example-files/lv2_partobs_cuqdyn_config.xml example-files/lv2_partobs_paper_data.txt
```

The exit code is the number of failing comparisons.

**Nobody needs MATLAB for any of the above**: the references are exported as
plain text under `golden/` and `baseline/matlab/`. MATLAB (R2024a) is only
needed to *regenerate* them (`gen_golden.m`, `baseline/gen_baseline.m`) when
the MATLAB reference itself changes.

## Where the figures are

In `baseline/`, one pair per model with the same layout (shaded band + best
fit + data markers; blue = observed/conformal state, orange = hidden/delta):

| Model | MATLAB | C (seed 1) |
|---|---|---|
| Lotka-Volterra | `matlab_lv2_hybrid_uq_plot.png` | `c_lv2_seed1_hybrid_uq_plot.png` |
| Alpha-pinene | `matlab_ap_hybrid_uq_plot.png` | `c_ap_seed1_hybrid_uq_plot.png` |
| SIR | `matlab_sir_hybrid_uq_plot.png` | `c_sir_seed1_hybrid_uq_plot.png` |
| NF-kB (15 panels) | `matlab_nfkb_hybrid_uq_plot.png` | `c_nfkb_seed1_hybrid_uq_plot.png` |

The `c_*_seed1_results.txt` files next to them are the C outputs those
figures were rendered from; any `cuqdyn-results.txt` can be re-rendered the
same way:

```bash
python3 validation/baseline/plot_c_results_matlab_style.py <results.txt> <data.txt> <out.png>
```

One visible convention: both sides clamp the lower band at 0 when plotting
(populations cannot be negative), so panels are comparable one to one.

## Layer 1 in detail: the golden vectors

`gen_golden.m` calls the MATLAB kernels on fixed synthetic inputs and writes
both inputs and outputs to `golden/`. `test_golden.c` feeds the same inputs
to the C kernels and compares. None of these kernels touch MEIGO or the ODE
solver — they are pure linear algebra — so the comparison is exact up to
library differences (LAPACK vs GSL).

Covered: `cuqdyn_fim_covariance` (9 cases: log/natural parameterization,
both covariance methods, an exactly rank-deficient Jacobian, the
non-positive-parameter fallback, an ill-conditioned NF-kB-style system), the
hybrid covariance (4 cases), the residual variance (4) and `quantile` (6
vectors × 9 probabilities — the conformal bands depend on it directly).

**How to read the tolerances.** The default is 1e-9 relative, scaled by the
largest magnitude of the expected array (element-wise ratios explode on
entries that are legitimately near zero). One case carries its own tolerance,
derived from theory rather than fitted to the observed number:
`fim_04_rank_deficient` builds an exactly singular J where only the ridge
(2e-10) makes J'J invertible; at cond = 1e12, LAPACK and GSL cannot agree
better than eps·cond ≈ 2e-4 however faithful the port is, so its tolerance is
1e-3. The lesson belongs to the *method*, not the port: **with a
near-singular FIM the numerical covariance is regularisation-dependent in any
implementation** — which is why `delta_bands.c` prints the rank and condition
number, and why on NF-kB the meaningful comparison is the bands, not the
element-wise covariance.

## What the validation deliberately does NOT cover

- **The weak-direction reliability diagnostic** (`local_reliability()` in
  MATLAB): not ported to C — `weak_fraction_threshold` is parsed from the XML
  but never read. `test_golden.c` prints `NOT IMPLEMENTED IN C` where it
  would apply, so the gap cannot quietly disappear.
- **The parametric bootstrap** (paper §2.7): not ported; tracked in TODO.
- **The PSD-clamp branch** of the hybrid covariance: none of the generated
  ensembles produces a negative eigenvalue, so it remains unexercised.
- **The MPI path** (LOO loop sharding) and `uq_method=hybridcov` end to end.

## Build gotcha on CESGA (Lustre)

Incremental builds on the scratch filesystem have occasionally produced a
`libcuqdyn-c.a` with a corrupted archive index (symbols present but not
indexed → `undefined reference to quantile / solve_ode`). Fix:

```bash
rm -f build-serial/modules/cuqdyn-c/libcuqdyn-c.a
make cuqdyn-c
```

## What a green run proves, and what it does not

It proves that the C UQ mathematics, the integration, the sensitivities and
the band-building stage reproduce MATLAB (layers 1-3, deterministic). What
remains outside is the internal search logic of sacess/eSS — a separately
published library — whose equivalence can only be claimed statistically
(layer 4), plus the paths listed in the section above.
