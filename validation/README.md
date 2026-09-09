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
| 1 | **Algebra kernels** | MATLAB's pure-math functions (`cuqdyn_fim_covariance`, the hybrid covariance, `cuqdyn_residual_variance`, `quantile`) were run once on fixed synthetic inputs and their inputs+outputs frozen in `layer1/cases/`. `test_golden.c` re-runs the C counterparts (`fim.c`, `matlab.c`) on the same inputs and diffs the outputs. | a transpilation bug in the linear algebra | none | ✅ **79/79** |
| 2 | **Integration & sensitivities** | MATLAB integrates each model with `ode15s` at the TRUE parameters and derives dy/dθ by complex step (exact); both are frozen in `layer2/matlab/<m>/`. `test_baseline.c` integrates the same ODE with CVODES, computes CVODES forward sensitivities, and diffs trajectory and each dy/dθ_k block. | wrong RHS (e.g. parameter order), integrator config, or broken sensitivities | none | ✅ 4/4 models |
| 3 | **Cost replay** | MATLAB runs one seeded eSS search with its cost wrapped in a recorder, freezing every θ_k the optimiser chose to evaluate together with MATLAB's cost J_k in `layer3/lv2_evals.txt`. `test_cost_replay.c` re-evaluates the C cost over the same sequence. All the randomness stayed on the MATLAB side, so the replay is exact — and it covers the cost function *inside* the optimisation loop, which layers 2 and 4 do not. | a bug in the cost function or its residual weighting | none | ✅ 20126/20126 within 1e-3 |
| 4 | **UQ replay** | One seeded full MATLAB run per model; its fitted θ̂, the entire LOO ensemble (per-refit trajectories, held-out residuals, refit parameters) and the resulting bands are frozen in `layer4/matlab/<m>/`. `test_baseline.c` **injects** θ̂ and the ensemble into the C band code (`conformal_bands()`, `delta_method_bands()`) and diffs bands, `Cov_p` and `std_y` against MATLAB's. Identical inputs → the optimiser is out of the equation. | a bug in the band mathematics (conformal quantiles, FIM covariance, delta propagation) | none | ✅ 4/4 models |
| 5 | **Statistical end-to-end** | Each side runs the FULL pipeline N times with different seeds (MATLAB: `gen_baseline(model, 5, 1:N)`; C: `layer5/run_c_seeds.sh model N`). `compare_baseline.py` compares the *distributions*: per-parameter median/IQR, band-width ratios per state, empirical coverage of the true trajectory. This is the only layer that exercises the eSS interface itself. | a systematic bias in the optimiser coupling — or nothing: two correct implementations still differ run to run | dominant (it is what is measured) | ✅ 10 seeds per side, 4 models: see layer5/report_*.md |

Key results of layers 2 and 4 (details and tolerances in `LAYERS.md`):

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
├── test_baseline.c    C comparator for layers 2 and 4 (the baseline_* ctests).
│                      One binary because both read the same config, data file
│                      and per-model context; it takes the validation directory
│                      and a model name and finds the rest itself.
├── gen_baseline.m     MATLAB generator of layers 2, 4 and 5, seeded and
│                      sequential. Writes into each layer's own tree.
├── plot_*.m / plot_*.py   render results the way the MATLAB side renders them;
│                      they span layers, hence living here rather than in one.
│
├── common/            WHAT EVERY LAYER SHARES.
│   ├── models/<model>/    the problem itself, per model (lv2, ap, sir, nfkb):
│   │                  times.txt, y0.txt, truth.txt, sigma.txt, observed_idx.txt,
│   │                  meta.txt and tol.txt (the comparison tolerances, editable
│   │                  without regenerating anything). Not layer material: these
│   │                  describe the problem, so layers 2, 4 and 5 all read them.
│   └── configs/       the XML/data pairs that example-files/ does not carry:
│                      the AP partially-observed example, and the NF-kB config
│                      with full-precision sigmas plus its matched eSS budget.
│
├── layer1/            ALGEBRA KERNELS.
│   ├── gen_golden.m       MATLAB generator of cases/
│   ├── test_golden.c      C comparator (the layer1_golden ctest)
│   └── cases/         one folder per test case (fim_01_small_log, hyb_01_plain,
│                      var_01_estimated, qnt_01...), each holding the plain-text
│                      INPUTS fed to the MATLAB kernel and the OUTPUTS it
│                      produced (expect_*.txt). A failure means the C algebra
│                      diverged from MATLAB on that exact input.
│
├── layer2/matlab/<model>/   INTEGRATION & SENSITIVITIES: trajectory and
│                      complex-step sensitivities at the TRUE parameters
│                      (traj.txt, sens.txt, theta_fixed.txt). No optimiser on
│                      either side.
│
├── layer3/            COST REPLAY.
│   ├── gen_cost_replay.m   records a seeded MATLAB eSS search
│   ├── test_cost_replay.c  re-evaluates the C cost over the same sequence
│   └── lv2_evals.txt       every theta the optimiser visited, with MATLAB's
│                      cost for it. The randomness stayed on the MATLAB side,
│                      so the replay is exact.
│
├── layer4/matlab/<model>/   UQ REPLAY: one seeded CUQDyn1_Plus run per model -
│                      theta_hat.txt, the whole LOO ensemble (loo_params.txt,
│                      media_matrix.txt, resid_loo.txt), the bands
│                      (q_low/q_up.txt), cov_p.txt and std_y.txt. test_baseline.c
│                      injects these into the C band code and compares.
│
└── layer5/            STATISTICAL END-TO-END, the only layer with both sides
    │                  stored, because each seed is a full expensive run.
    ├── matlab/<model>/seed_N/   MATLAB's side: theta_hat, params_median, bands
    ├── c/<model>/seed_N/        this port's side, written by run_c_seeds.sh:
    │                  cuqdyn-results.txt in the CLI's labelled-section format,
    │                  plus sacess/convergence_id0.csv. run.log is gitignored.
    ├── run_c_seeds.sh          N seeded CLI runs into c/<model>/
    ├── compare_baseline.py     compares the two distributions, writes the report
    ├── drago_baseline.sbatch   SLURM job for the MATLAB side
    ├── report_<model>.md       the verdict per model: medians and IQRs on both
    │   + _theta.png            sides, band widths, empirical coverage
    ├── hybrid/        THE SHARED-OPTIMISER EXPERIMENT. cost_server.c serves the
    │                  real C cost over TCP and hybrid_meigo_cvodes.m has
    │                  MATLAB's MEIGO optimise against it, which separates a
    │                  model difference from an optimiser one.
    │                  hybrid_report_<model>.txt holds the outcome.
    └── *.png / *.fig  the side-by-side band figures, one pair per model, and
                       the seed-1 C results they were rendered from
```

One directory per layer, each holding what that layer needs and nothing else.
Inside a layer, `matlab/` is the frozen reference and `c/` what this port
produced — only layer 5 has both, because it is the only stage whose C output
is worth keeping; the rest compute theirs and compare it in the same run. What
does not belong to a single layer lives in `common/`, and the two tools that
span layers sit at the top.

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
scripts/build.sh serial
cd build/release-serial && ctest -R "layer1|baseline|cost_replay" --output-on-failure
```

- `layer1_golden` — layer 1. A failure = a transpilation bug in the
  algebra.
- `baseline_lv2` / `baseline_ap` / `baseline_sir` / `baseline_nfkb` — layers
  2 and 4 per model, in one binary. Whichever of the two has no MATLAB export
  is skipped; with neither the test reports SKIP (they are included in this
  branch, so they should actually run).
- `cost_replay_lv2` — layer 3.

Layer 5 is not a ctest: it is a report to read, not a gate. See below.

For the per-check table, run the binaries directly:

```bash
./build/release-serial/validation/test_golden validation/layer1/cases 1e-9
./build/release-serial/validation/test_baseline validation lv2 \
    example-files/lv2-partobs/cuqdyn-fim.xml example-files/lv2-partobs/data.txt
```

The exit code is the number of failing comparisons.

**Nobody needs MATLAB for any of the above**: the references are exported as
plain text under `layer1/cases/` and `layer<N>/matlab/`. MATLAB (R2024a) is only
needed to *regenerate* them (`layer1/gen_golden.m`, `gen_baseline.m`) when
the MATLAB reference itself changes.

## Where the figures are

In `layer5/`, one pair per model with the same layout (shaded band + best
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
python3 validation/plot_c_results_matlab_style.py <results.txt> <data.txt> <out.png>
```

One visible convention: both sides clamp the lower band at 0 when plotting
(populations cannot be negative), so panels are comparable one to one.

## Layer 1 in detail: the golden vectors

`gen_golden.m` calls the MATLAB kernels on fixed synthetic inputs and writes
both inputs and outputs to `layer1/cases/`. `test_golden.c` feeds the same inputs
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
rm -f build/release-serial/modules/cuqdyn-c/libcuqdyn-c.a
make cuqdyn-c
```

## What a green run proves, and what it does not

It proves that the C UQ mathematics, the integration, the sensitivities and
the band-building stage reproduce MATLAB (layers 1-3, deterministic). What
remains outside is the internal search logic of sacess/eSS — a separately
published library — whose equivalence can only be claimed statistically
(layer 4), plus the paths listed in the section above.
