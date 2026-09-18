# Validating the C port against the MATLAB reference

The C/Rust code in this repository is a transpilation of the MATLAB in
`CUQDyn1_Plus/` and `CUQDyn/`. This directory checks that the transpilation is
faithful, on the four models of the CUQDyn1_Plus preprint: `lv2`
(Lotka-Volterra, one state hidden), `ap` (alpha-pinene, y5 hidden), `sir`
(only the infected observed) and `nfkb` (15 states, 10 observed, near-singular
FIM).

**Status: every deterministic layer is green** — 79/79 kernel checks and
71/71 pipeline checks (lv2 12, ap 12, sir 10, nfkb 37), about 6 seconds of
`ctest`. Layer 5 (the C pipeline driven by MATLAB's MEIGO), full budgets on lv2, ap and
sir (71 launches in all): both sides evaluate the same θ sequence for 70-150
evaluations per launch with the two costs agreeing to ~1e-9 (1.2e-6 worst),
**no cost mismatch on any identical prefix**, then a rounding difference flips
an eSS decision; after it 58 launches reach the same optimum (θ\* within 1e-4)
and 13 a neighbouring one with J equal to ~1e-5 relative (lv2 5, ap 7 - the
flat basins of those problems, sir 0). Final θ̂, medians and bands agree to
1e-4 (lv2), 8e-4 (ap) and 1e-7 (sir). On nfkb (37 launches) the identical prefix is 651-669 evaluations — the length the hybrid experiment found — with the costs agreeing to 3e-6 (3.1e-4 worst, the stiff model's integration tolerance) and no mismatch on any prefix; after the flip every launch lands in a different basin of its non-identifiable landscape (θ\* up to 30× apart, J within 20-50%), so its final outputs (20-27% apart) are informative only, as designed. The two MATLAB pipeline runs of nfkb, launched independently with the same seeds, were byte-identical. Layer 6 (statistical: the production CLI with sacess against MATLAB with MEIGO, 10 seeds per side, matched budgets): lv2, ap and sir agree — LOO-median parameters 1.000, band widths 1.000-1.004, empirical coverage 1.000 on both sides, θ̂ of the full fit within 0.4% (lv2, where the two local solvers differ); nfkb spreads as its non-identifiability dictates (parameter medians 0.3-15× apart between the two optimisers, observed-state band widths 0.95-1.08, hidden-state ones 0.7-5.7×) with coverage 1.000 on all 15 states on both sides.
Nothing here needs MATLAB to run the checks: the references are exported as
plain text.

## Why a naive end-to-end comparison does not work

The obvious validation — run the CLI, run `CUQDyn1_Plus.m`, diff the bands —
fails, because eSS is a stochastic global optimiser: two runs of the *same*
implementation with different seeds already produce different parameters and
different bands. In a direct MATLAB-vs-C diff, optimiser noise buries any real
transpilation bug.

The fix is to compare in layers, removing the noise wherever possible. Each
layer freezes everything the previous one could not.

| Layer | Name | What is done | A failure means | Optimiser noise |
|---|---|---|---|---|
| 1 | Algebra kernels | MATLAB's pure-math functions (`cuqdyn_fim_covariance`, the hybrid covariance, `cuqdyn_residual_variance`, `quantile`) run once on fixed synthetic inputs; inputs and outputs frozen in `layer1/cases/`. `test_golden.c` re-runs the C counterparts (`fim.c`, `matlab.c`) on the same inputs. | a transpilation bug in the linear algebra | none |
| 2 | Integration and sensitivities | MATLAB integrates each model with `ode15s` at the TRUE parameters and derives dy/dθ by complex step (exact); frozen in `layer2/matlab/<m>/`. `test_baseline.c` integrates with CVODES, computes CVODES forward sensitivities and diffs the trajectory and each dy/dθ_k block. | wrong right-hand side (parameter order), integrator configuration, broken sensitivities | none |
| 3 | Cost replay | MATLAB runs one seeded eSS search with its cost wrapped in a recorder, freezing every θ the optimiser evaluated together with MATLAB's cost in `layer3/lv2_evals.txt`. `test_cost_replay.c` re-evaluates the C cost over the same sequence. All the randomness stayed on the MATLAB side, so the replay is exact. | a bug in the cost function or its residual weighting | none |
| 4 | UQ replay | One seeded full MATLAB run per model; θ̂, the whole LOO ensemble and the resulting bands are frozen in `layer4/matlab/<m>/`. `test_baseline.c` injects θ̂ and the ensemble into the C band code (`conformal_bands()`, `delta_method_bands()`) and diffs bands, `Cov_p` and `std_y`. Identical inputs, so the optimiser is out of the equation. | a bug in the band mathematics (conformal quantiles, FIM covariance, delta propagation) | none |
| 5 | Shared-optimiser end-to-end | The C pipeline runs as the CLI itself with its optimiser replaced by MATLAB's MEIGO over TCP (`layer5/pipeline_meigo.c` defines `execute_ess_solver`, the one function through which `cuqdyn_algo` reaches the optimiser). A minimal MATLAB copy of the pipeline runs the same launches with the same per-launch seeds, both sides integrating with CVODES. `layer5/compare_lockstep.py` diffs the evaluation traces launch by launch and then the final outputs. | a divergence before any rounding flip is an orchestration bug in C (which point is left out, how the ensemble is assembled); after a flip only the optimum is compared | none until a rounding difference flips an eSS decision; bounded per launch by the per-launch seeds |
| 6 | Statistical end-to-end | Each side runs the FULL pipeline N times with different seeds; `layer6/compare_baseline.py` compares the distributions (per-parameter median and IQR, band widths, empirical coverage). The only layer that exercises the sacess/eSS interface itself. | a systematic bias in the optimiser coupling — or nothing: two correct implementations still differ run to run | dominant: it is what is measured |

Layers 1-4 and the layer-5 loopback are `ctest` gates. Layers 5 and 6 are
reports to read, not gates.

Key results of layers 2 and 4: conformal bands machine-exact on all four
models; trajectories and sensitivities agree to 1e-7..1e-4 (two correct
integrators at rtol 1e-6); delta-method bands of hidden states to 1e-5 (2.9% on
NF-kB, consistent with its cond(FIM) ~ 3e8).

## What is in each directory

```
validation/
├── README.md
├── CMakeLists.txt        the ctests (layer1_golden, layer2_4_<model>, layer3_lv2,
│                         layer5_loopback_lv2)
├── test_baseline.c       C comparator for layers 2 and 4 (one binary: same config,
│                         data file and per-model context)
├── textio.h              checked text-to-number readers shared by the C harnesses
├── gen_baseline.m        MATLAB generator of layers 2, 4 and 6, seeded and sequential
├── plot_matlab_vs_c.m, plot_c_hybrid_uq.m, plot_c_results_matlab_style.py
│                         render results the way the MATLAB side renders them
│
├── common/               what every layer shares
│   ├── models/<model>/   the problem: times.txt, y0.txt, truth.txt, sigma.txt,
│   │                     observed_idx.txt, meta.txt, tol.txt (comparison tolerances,
│   │                     editable without regenerating anything)
│   └── configs/          XML/data pairs example-files/ does not carry: the AP
│                         partially-observed example, the NF-kB config with
│                         full-precision sigmas, and eSS configs whose budget
│                         matches MATLAB's (*_ess_serial_2e4.xml)
│
├── layer1/               gen_golden.m, test_golden.c, cases/<case>/ (inputs + expect_*.txt)
├── layer2/matlab/<m>/    traj.txt, sens.txt, theta_fixed.txt
├── layer3/               gen_cost_replay.m, test_cost_replay.c, lv2_evals.txt
├── layer4/matlab/<m>/    theta_hat.txt, loo_params.txt, media_matrix.txt, resid_loo.txt,
│                         media_tot.txt, observed_data.txt, q_low.txt, q_up.txt,
│                         cov_p.txt, std_y.txt
├── layer5/               the C pipeline driven by MATLAB's MEIGO
│   ├── pipeline_meigo.c      execute_ess_solver() as a TCP client to MATLAB; compiled
│   │                         with the CLI's own sources into the pipeline_meigo binary
│   ├── loopback_check.sh     the ctest: the same binary with a built-in stand-in optimiser
│   ├── matlab/               problem_def.m (one problem for both MATLAB roles),
│   │                         meigo_server.m (MEIGO serving the C pipeline),
│   │                         run_pipeline_cvodes.m + loo_ensemble_seeded.m +
│   │                         uq_cvodes.m + sensitivities_cvodes.m + cvodes_solver.m
│   │                         (the MATLAB pipeline copy), write_matrix.m
│   ├── compare_lockstep.py   launch-by-launch comparison of the two traces, the report
│   ├── run_layer5.sh, drago_layer5.sbatch
│   └── hybrid/               the single-fit precursor: cost_server.c serves the real
│                             C cost over TCP, hybrid_meigo_cvodes.m has MATLAB's MEIGO
│                             optimise against it; hybrid_report_<model>.txt
└── layer6/               the statistical end-to-end comparison: run_c_seeds.sh (C side),
                          compare_baseline.py (the report), drago_baseline.sbatch
                          (MATLAB side on SLURM)
```

Run outputs (`layer5/c/<m>/`, `layer5/matlab/<m>/`, `layer6/matlab/<m>/seed_N/`,
`layer6/c/<m>/seed_N/`, the reports and figures) are not versioned: every run is
a full stochastic pipeline. They stay on the machines that produced them.

## Running the validation

The top-level `CMakeLists.txt` does not register this directory; add one line
after `add_subdirectory(tests)`:

```cmake
add_subdirectory(validation)
```

Then build and test (`scripts/build.sh` defaults to a debug build, so name the
type):

```bash
scripts/build.sh serial release
cd build/release-serial && ctest -R "layer1|layer2_4|layer3|layer5_loopback" --output-on-failure
```

- `layer1_golden` — layer 1. A failure is a transpilation bug in the algebra.
- `layer2_4_<model>` — layers 2 and 4 per model, in one binary. Whichever of
  the two has no MATLAB export is skipped; with neither, the test reports SKIP
  (exit 77).
- `layer3_lv2` — layer 3 (lv2 only).
- `layer5_loopback_lv2` — the layer-5 binary with its optimiser answered by a
  built-in loopback (returns a fixed θ): the whole plumbing of the pipeline
  with a substituted optimiser, without MATLAB.

For the per-check table, run the binaries directly:

```bash
./build/release-serial/validation/test_golden validation/layer1/cases 1e-9
./build/release-serial/validation/test_baseline validation lv2 \
    example-files/lv2-partobs/cuqdyn-fim.xml example-files/lv2-partobs/data.txt
```

The exit code is the number of failing comparisons. Every MATLAB export is
shape-checked before it is indexed, so a stale or truncated reference fails
with a message rather than reading past the end of a matrix.

Layer 5 (needs MATLAB with MEIGO64 on the same machine):

```bash
validation/layer5/run_layer5.sh lv2 [port] [base_seed]
# or, on drago:  sbatch --export=ALL,MODEL=lv2 validation/layer5/drago_layer5.sbatch
```

It starts `pipeline_meigo` — the CLI with its optimiser swapped — has MATLAB's
MEIGO drive it (`meigo_server.m`), then runs the MATLAB pipeline copy with the
same seeds (`run_pipeline_cvodes.m`) and writes `layer5/report_<model>.md`.
Every launch k (0 = the full fit, then each leave-one-out refit in order) is
seeded `base_seed + k` on both sides, so a rounding flip in one launch cannot
contaminate the next. On the C side each `eval` goes through the library's
real `obj_func`; on the MATLAB side through the published `prob_mod_cost_*`,
both integrating with CVODES (BDF, dense, the XML tolerances). The MATLAB copy
computes its sensitivities with CVODES too (`odeSensitivity`), like the C port;
they agree with the layer-2 complex-step references to ~1e-4 and reproduce the
layer-4 delta bands to ~1e-5. `CUQDYN_L5_MAXEVAL=300` shrinks the budget for a
smoke run of the whole chain.

Layer 6, C side and report:

```bash
validation/layer6/run_c_seeds.sh lv2 10          # SACESS_SEED=1..10
python3 validation/layer6/compare_baseline.py lv2
```

`run_c_seeds.sh` and `run_layer5.sh` use the budget-matched eSS configs in
`common/configs/` (20000 evaluations for lv2, sir and nfkb, 10000 for ap — the
same numbers `gen_baseline.m` and `problem_def.m` give MEIGO), not the smaller
budgets of `example-files/`.

## Regenerating the references (MATLAB only)

Only needed when the MATLAB reference itself changes. Requirements: MATLAB
R2024a or later with the Optimization Toolbox; MEIGO64 from `$MEIGO64_PATH` or
`CUQDyn/Matlab/MEIGO64-master`.

```matlab
cd validation
layer1/gen_golden('layer1/cases')     % layer 1
gen_baseline('lv2')                   % layers 2 and 4 (default)
gen_baseline('nfkb', [2 4])
gen_baseline('sir', 5, 1:10)          % layer 6, seeds 1..10 (the "5" is gen_baseline's own id for it)
layer3/gen_cost_replay('lv2')         % layer 3
```

On drago.csic.es (SLURM):

```bash
sbatch --export=ALL,MODEL=nfkb,LAYERS="[2 4]" validation/layer6/drago_baseline.sbatch
sbatch --array=1-20 --export=ALL,MODEL=nfkb,LAYERS=5 validation/layer6/drago_baseline.sbatch
```

Each array task runs one seed in its own `seed_<k>/` (re-launchable; finished
seeds are skipped). Override the module name with `MATLAB_MODULE=` if it is
not `MATLAB/2024b`.

Provenance of the current references: layers 1-4 and the layer-6 seeds of
lv2, ap, sir and nfkb 1-10 were produced with MATLAB R2024a; nfkb seeds 11-20
and the layer-5 runs with R2024b on drago.

## Tolerances and how to read a failure

Per model, in `common/models/<model>/tol.txt`:

| Key | lv2 / sir | ap | nfkb | Why |
|---|---|---|---|---|
| `layer2_traj` | 1e-4 | 5e-4 | 5e-4 | both integrate at RelTol 1e-6; two correct solvers agree to that order (ap has a long horizon with tiny rate constants) |
| `layer2_sens` | 5e-3 | 1e-2 | 1e-2 | complex step is exact, CVODES sensitivities carry their own integration error |
| `layer4_conformal` | 1e-9 | 1e-9 | 1e-9 | identical inputs and the same quantile algorithm: more than this is a bug |
| `layer4_delta` | 1e-2 | 5e-2 | 1e-1 | inherits the sensitivity error through the inverse of the FIM |
| `layer4_covp` | (= delta) | (= delta) | 1e3 | at cond(FIM) ~ 3e8 the element-wise covariance is regularisation-dominated on both sides; the bands and `std_y` are the meaningful comparison |
| `layer5_cost` | 1e-5 | 1e-5 | 1e-3 | how far the two CVODES builds may disagree on J at the same θ in the lock-step check: ~1e-9 typically, ~1e-6 at the worst points of a search, but up to 3e-4 on the stiff nfkb (its trajectories already differ by 5e-4, `layer2_traj`); a wrong data slice moves J by ~1/m, orders of magnitude more |

Layer 1 uses 1e-9 relative, scaled by the largest magnitude of the expected
array. One case carries its own tolerance derived from theory:
`fim_04_rank_deficient` builds an exactly singular J where only the ridge
(2e-10) makes J'J invertible; at cond = 1e12, LAPACK and GSL cannot agree
better than eps·cond ≈ 2e-4, so its tolerance is 1e-3. The lesson belongs to
the method: with a near-singular FIM the numerical covariance is
regularisation-dependent in any implementation, which is why `delta_bands.c`
prints the rank and condition number.

Layer 5 reads the two evaluation traces of each launch: "the same evaluation"
is θ within 1e-12 relative, "the same cost" J within `layer5_cost` of `tol.txt`, "the same optimum"
θ\* within 1e-4. A cost mismatch inside the identical prefix (same θ, different
J) is flagged as an orchestration bug: the C side evaluated something else
than the MATLAB side for the same launch.

Diagnosis:

- `conformal q_low/q_up` fails → `conformal_bands.c` or `matlab.c:quantile`.
  The cleanest possible signal: identical inputs.
- `trajectory` fails but the sensitivities do not → integrator configuration
  (compare the XML with `opts.ode`) or the ODE itself (parameter order — see
  the warning below).
- `sens dtheta_k` fails for some k → CVODES sensitivity precision on those
  parameters; if they are the tiny-scale ones, look at `pbar`.
- only `cov_p` / `std_y` / `delta` fail with layer 2 green → the difference is
  amplified in the FIM: read the `rank` and `condition number` the harness
  prints before suspecting the code.
- `sigma XML vs MATLAB` fails → the `<sigma>` in the config does not match what
  MATLAB derives; everything else fails in cascade. Fix the XML.
- layer 5 reports a cost mismatch before any flip → compare the two `evals_<k>.txt`
  at that row: the θ is the same, so the difference is in what C fed to
  `obj_func` for that launch (the held-out point, the data slice, the weights).

Do not use `example-files/lotka-volterra/` to compare with MATLAB: its compiled
Rust model swaps p3 and p4 with respect to `prob_mod_dynamics_LV.m`. The
baseline uses `example-files/lv2-partobs/`, which defines the ODE by
expressions and does match. The compiled `nfkb` model is verified term by term.

## Reproducibility

- MATLAB: `rng(seed, 'twister')` and a SEQUENTIAL LOO loop
  (`use_parallel = false`; with `parfor` the stream is split across workers and
  is not repeatable). Layer 3 uses the fixed seed 20260828, layer 4 the fixed
  seed 20260819, layer 6 the seeds 1..N.
- Layer 5: base seed 20260917; launch k is seeded `base_seed + k` on both
  sides, immediately before MEIGO starts.
- C: `SACESS_SEED=<k>` (set by `run_c_seeds.sh`).
- Seeds on one side do not correspond to seeds on the other in layer 6, which
  is why it compares distributions.
- Optimiser budgets are matched between sides (`maxeval` in `gen_baseline.m` /
  `problem_def.m` = `<maxevaluation>` of the eSS config the harness uses).

## The shared-optimiser experiment (layer5/hybrid)

The single-fit precursor of layer 5. MATLAB's MEIGO runs twice with the same
seed: once evaluating the MATLAB cost (the `ode` object with `cvodesstiff`,
tolerances from the XML) and once evaluating the real C cost served over TCP by
`cost_server` (the CLI's own code path, returning J and the residuals so
`lsqnonlin` works too). All the randomness is generated by MATLAB. Costs agree
along the common prefix to 1e-10 (lv2), 1.5e-9 (ap), 1e-6 (sir) and 3.7e-6
(nfkb), in lock-step for 123, 148, 74 and 656 evaluations until a rounding
difference flips a discrete eSS decision. After the divergence lv2, ap and sir
land on the same optimum (θ̂ within 1e-7..3e-4); nfkb ends in different basins
of its non-identifiable landscape (J 914 vs 518, the C-cost run found the
better one), measuring the problem's multimodality rather than the code.
Details in `layer5/hybrid/hybrid_report_<model>.txt`.

## What is known to differ, and what is not covered

- **LOO refit starting point.** The C port warm-starts every leave-one-out
  refit from θ̂ (`cuqdyn.c`), as the original CUQDyn1 did; CUQDyn1_Plus starts
  every global refit from the user's initial guess (`cuq_loo_ensemble.m`). The
  Plus behaviour is the reference; the C change is tracked separately. Layer 4
  is unaffected (it injects MATLAB's ensemble); layer 5 starts every launch
  from the guess on both sides (the substituted optimiser ignores the warm
  start); layer 6 measures the production C as it is, warm start included.
- **Layer 6 compares two different optimisers** (sacess with `dhc`, MEIGO with
  `lsqnonlin`), each with its own randomness, so its numbers are what they are:
  on nfkb the parameter medians differ up to 15× between the two because the
  problem is non-identifiable, not because of the port — layer 5 is the
  deterministic check of the same pipeline. The reports are regenerated by
  `layer6/compare_baseline.py` and not versioned.
- **Local solver.** MEIGO uses `lsqnonlin`, the sacess configs use `dhc`. Both
  search in log scale. This is a legitimate difference between two optimisers
  and belongs to what layer 6 measures; layer 5 removes it by using MEIGO on
  both sides.
- **The weak-direction reliability diagnostic** (`local_reliability()` in
  `cuqdyn_fim_covariance.m`, Algorithm 4 step 8 of the paper) is not ported:
  `weak_fraction_threshold` is parsed from the XML but never read.
  `test_golden.c` prints `NOT IMPLEMENTED IN C` where it would apply.
- **The parametric bootstrap** (`bootstrap_trajectory_uq.m`, paper section
  2.7): an optional post-fit workflow, not ported.
- **The PSD-clamp branch** of the hybrid covariance: none of the generated
  ensembles produces a negative eigenvalue, so it remains unexercised.
- **The MPI path** (LOO loop sharding): validated separately by
  `scripts/test-mpi.sh` on the `feat/mpi-ci-validation` branch, not here.
- `uq_method=hybridcov` end to end (the hybrid covariance kernel itself is
  covered in layer 1).

## Build gotcha on Lustre file systems

Incremental builds on a Lustre scratch have occasionally produced a
`libcuqdyn-c.a` with a corrupted archive index (symbols present but not
indexed, `undefined reference to quantile / solve_ode`). Fix:

```bash
rm -f build/release-serial/modules/cuqdyn-c/libcuqdyn-c.a
make cuqdyn-c
```

## What a green run proves, and what it does not

It proves that the C UQ mathematics, the integration, the sensitivities and
the band-building stage reproduce MATLAB (layers 1-4, deterministic), and that
the C orchestration of the pipeline makes the same decisions as the MATLAB
one when both are handed the same optimiser (layer 5, deterministic up to
rounding flips). What remains outside is the internal search logic of
sacess/eSS — a separately published library — whose equivalence can only be
claimed statistically (layer 6), plus the items listed in the previous section.
