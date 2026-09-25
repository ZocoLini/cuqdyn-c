# Validating the C port against the MATLAB reference

The C/Rust code in this repository is a transpilation of the MATLAB in
`CUQDyn1_Plus/` and `CUQDyn/`. This directory checks that the transpilation is
faithful, on the four models of the CUQDyn1_Plus preprint: `lv2`
(Lotka-Volterra, one state hidden), `ap` (alpha-pinene, y5 hidden), `sir`
(only the infected observed) and `nfkb` (15 states, 10 observed, near-singular
FIM).

**Status: every deterministic layer is green** — 79/79 kernel checks and
71/71 pipeline checks (lv2 12, ap 12, sir 10, nfkb 37), about 6 seconds of
`ctest`. Layer 5 (the C pipeline driven by MATLAB's MEIGO with `dhc`, full
budgets, 108 launches over the four problems): **no cost mismatch on any
identical prefix**. On lv2 (31 launches) both sides evaluate the same θ
sequence for 1390-20814 evaluations per launch and 8 launches stay in
lock-step to the very end (463 024 identical evaluations in all, the two costs
agreeing to 5e-9 in the median, 3.4e-5 worst); after a rounding difference
flips an eSS decision, 19 launches reach the same optimum (θ\* within 1e-4)
and 4 a neighbouring one with J equal to 8e-5 relative. On sir (31 launches)
the identical prefix is 179-2743 evaluations and all 31 reach the same
optimum; on ap (9 launches) it is 348-1173, 3 reach the same optimum and 6 a
neighbouring one with J equal to 6e-8 (its flat basin). Final θ̂, medians and
bands agree to 6e-3 (lv2, whose ensemble holds the 4 neighbouring optima),
7e-4 (ap) and 7e-8 (sir). On nfkb (37 launches) the identical prefix is
638-726 evaluations — the length the hybrid experiment found — with the costs
agreeing to 3.4e-6 (3.1e-4 worst, the stiff model's integration tolerance);
after the flip every launch lands in a different basin of its non-identifiable
landscape (J 0.3-76% apart), so its final outputs (θ̂ 10%, medians 7%, bands
56%, Cov_p 75%) are informative only, as designed. Layer 6 (statistical: the production CLI with sacess against MATLAB with MEIGO, 10 seeds per side, matched budgets): lv2, ap and sir agree — LOO-median parameters 1.000, band widths 1.000-1.004, empirical coverage 1.000 on both sides, θ̂ of the full fit within 0.4% (lv2, where the two local solvers differ); nfkb spreads as its non-identifiability dictates (parameter medians 0.3-15× apart between the two optimisers, observed-state band widths 0.95-1.08, hidden-state ones 0.7-5.7×) with coverage 1.000 on all 15 states on both sides.
Layers 1-4 need no MATLAB: their references are versioned as plain text.

Everything is driven by one script, `validation/run_validation.sh`:

| I want to... | Section |
|---|---|
| check the port in ten minutes, without MATLAB | [Quick start](#quick-start-layers-1-4-no-matlab) |
| run the end-to-end layers (MATLAB, hours, a cluster helps) | [Full validation](#full-validation-layers-5-and-6) |
| know where a result was written | [Where results go](#where-results-go) |
| validate another problem | [Adding a problem](#adding-a-problem) |

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
| 1 | Algebra kernels | MATLAB's pure-math functions (`cuqdyn_fim_covariance`, the hybrid covariance, `cuqdyn_residual_variance`, `quantile`) run once on fixed synthetic inputs; inputs and outputs frozen in `references/golden.txt`. `test_golden.c` re-runs the C counterparts (`fim.c`, `matlab.c`) on the same inputs. | a transpilation bug in the linear algebra | none |
| 2 | Integration and sensitivities | MATLAB integrates each model with `ode15s` at the TRUE parameters and derives dy/dθ by complex step (exact); frozen in the layer-2 sections of `references/<m>.txt`. `test_baseline.c` integrates with CVODES, computes CVODES forward sensitivities and diffs the trajectory and each dy/dθ_k block. | wrong right-hand side (parameter order), integrator configuration, broken sensitivities | none |
| 3 | Cost replay | MATLAB runs one seeded eSS search with its cost wrapped in a recorder, freezing every θ the optimiser evaluated together with MATLAB's cost in `references/lv2_evals.txt`. `test_cost_replay.c` re-evaluates the C cost over the same sequence. All the randomness stayed on the MATLAB side, so the replay is exact. | a bug in the cost function or its residual weighting | none |
| 4 | UQ replay | One seeded full MATLAB run per model; θ̂, the whole LOO ensemble and the resulting bands are frozen in the layer-4 sections of `references/<m>.txt`. `test_baseline.c` injects θ̂ and the ensemble into the C band code (`conformal_bands()`, `delta_method_bands()`) and diffs bands, `Cov_p` and `std_y`. Identical inputs, so the optimiser is out of the equation. | a bug in the band mathematics (conformal quantiles, FIM covariance, delta propagation) | none |
| 5 | Shared-optimiser end-to-end | The C pipeline runs as the CLI itself with its optimiser replaced by MATLAB's MEIGO over TCP (`c/pipeline_meigo.c` defines `execute_ess_solver`, the one function through which `cuqdyn_algo` reaches the optimiser). A minimal MATLAB copy of the pipeline runs the same launches with the same per-launch seeds, both sides integrating with CVODES. `tools/compare_lockstep.py` diffs the evaluation traces launch by launch and then the final outputs. | a divergence before any rounding flip is an orchestration bug in C (which point is left out, how the ensemble is assembled); after a flip only the optimum is compared | none until a rounding difference flips an eSS decision; bounded per launch by the per-launch seeds |
| 6 | Statistical end-to-end | Each side runs the FULL pipeline N times with different seeds; `tools/compare_baseline.py` compares the distributions (per-parameter median and IQR, band widths, empirical coverage). The only layer that exercises the sacess/eSS interface itself. | a systematic bias in the optimiser coupling — or nothing: two correct implementations still differ run to run | dominant: it is what is measured |

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
├── run_validation.sh     the single entry point: build, layer N, references, report
├── CMakeLists.txt        the ctests (layer1_golden, layer2_4_<model>, layer3_lv2,
│                         layer5_loopback_lv2)
├── cmake/register.cmake  registers this directory in a build without editing the
│                         top-level CMakeLists.txt
│
├── input_validation/     one directory per problem, everything a run needs
│   └── <name>/           cuqdyn.xml, sacess.xml, data.txt (the C side, with the
│                         eSS budget matched to MATLAB's) and problem.conf (where
│                         the MATLAB side lives, relative to --matlab_repo);
│                         lv2, ap, sir and nfkb are the presets of --problem=
├── references/           the frozen MATLAB references of layers 1-4 (see
│   │                     "The reference files" below)
│   ├── golden.txt        layer 1: every case, [<case>/<array>] sections + [manifest]
│   ├── <name>.txt        one file per problem: the problem itself ([meta], [times],
│   │                     [y0], [observed_idx], [sigma], [truth]), layer 2
│   │                     ([theta_fixed], [traj], [sens]) and layer 4 ([theta_hat],
│   │                     [loo_params], [resid_loo], [media_tot], [q_low], [q_up],
│   │                     [cov_p], [std_y], [observed_data], [media_matrix], [meta4])
│   ├── lv2_evals.txt     layer 3: the recorded MATLAB eSS search (lv2 only)
│   └── tolerances.txt    the comparison tolerances, one [<name>] section per
│                         problem, maintained by hand
├── c/                    the C comparators
│   ├── test_golden.c         layer 1
│   ├── test_baseline.c       layers 2 and 4 (one binary: same config, data file
│   │                         and per-model context)
│   ├── test_cost_replay.c    layer 3
│   ├── pipeline_meigo.c      layer 5: execute_ess_solver() as a TCP client to
│   │                         MATLAB, compiled with the CLI's own sources
│   ├── loopback_check.sh     the layer-5 ctest: the same binary with a built-in
│   │                         stand-in optimiser
│   ├── cost_server.c         the shared-optimiser experiment: the real C cost
│   │                         served over TCP
│   ├── refio.h               reader of the packed reference files ([name] sections)
│   └── textio.h              checked text-to-number readers
├── matlab/               the MATLAB side
│   ├── load_problem.m        the MATLAB side of a problem, from its directory
│   ├── check_problem.m       do both sides define the same problem?
│   ├── gen_golden.m          generator of layer 1
│   ├── gen_baseline.m        generator of layers 2, 4 and 6, seeded and sequential
│   ├── gen_cost_replay.m     generator of layer 3
│   ├── read_sections.m, read_section_*.m, write_section_*.m
│   │                         the packed reference files, both directions
│   ├── layer5_problem.m, meigo_server.m, run_pipeline_cvodes.m,
│   │   loo_ensemble_seeded.m, uq_cvodes.m, sensitivities_cvodes.m,
│   │   cvodes_solver.m, write_matrix.m, write_trace.m
│   │                         layer 5: MEIGO serving the C pipeline, and the
│   │                         minimal pipeline copy
│   ├── hybrid_meigo_cvodes.m the shared-optimiser experiment (MEIGO against
│   │                         cost_server); its report goes under results/hybrid/
│   └── plot_matlab_vs_c.m, plot_c_hybrid_uq.m
│                             render results the way the MATLAB side renders them
├── tools/                problem_info.py (the C side of a problem as plain text),
│                         compare_lockstep.py (the layer-5 report),
│                         compare_baseline.py (the layer-6 report),
│                         plot_c_results_matlab_style.py, slurm_job.sh (the job
│                         --sbatch submits)
└── results/              everything a run writes (not versioned; see "Where results go")
```

What is versioned is the harness, the inputs of the four problems and the
references of layers 1-4: seven plain text files under `references/`, about
3 MB, regenerated by script. Run outputs are not: every run of layers 5 and 6 is a
full stochastic pipeline, and they stay on the machines that produced them.

### The reference files

A reference file is a sequence of sections. A section starts with a line
`[name]` and holds one array (`rows cols` — or `n1 n2 n3` for the 3-D
sensitivities and LOO trajectories — followed by the values row by row,
`%.17g`) or `key value` lines. The C side reads them with `c/refio.h`, MATLAB
with `matlab/read_sections.m`; the generators write them with
`matlab/write_section_*.m`. Regenerating one layer of a problem rewrites its
sections and keeps the others, so `git diff` shows exactly what moved.

## Quick start: layers 1-4, no MATLAB

What you need is what the project itself needs to build: GCC/GFortran up to 13,
CMake 3.26-3.31, Rust 1.85 or later, make. Every command is told where
cuqdyn-c is installed (`--c_repo=DIR`, the repository); nothing is guessed from
the location of the script:

```bash
C=$HOME/cuqdyn-c
validation/run_validation.sh build   --c_repo=$C   # ~10 min the first time (GSL, HDF5, CVODES)
validation/run_validation.sh layer 1 --c_repo=$C   # algebra kernels, 79 checks
validation/run_validation.sh layer 2 --c_repo=$C   # integration + sensitivities, and layer 4
validation/run_validation.sh layer 3 --c_repo=$C   # cost replay (lv2)
validation/run_validation.sh layer 4 --c_repo=$C   # the same comparator as layer 2
```

Each command prints the per-check table, exits non-zero if a check fails and
leaves the table under `validation/results/`. If your compilers are not on
`PATH`, put what sets them up in a file and pass `--env=FILE` to every command
(on a cluster: the `module load` lines).

The references those layers compare against are versioned; with MATLAB and the
CUQDyn1_Plus installation at hand they are regenerated by the same script (see
[Regenerating the references](#regenerating-the-references-matlab-only)):

```bash
M=$HOME/CUQDyn1_Plus
validation/run_validation.sh references --c_repo=$C --matlab_repo=$M   # all four, layer 4 is hours
```

`build` configures `build/release-serial/` with
`-DCMAKE_PROJECT_cuqdyn_INCLUDE=validation/cmake/register.cmake`, which registers
this directory without touching the top-level `CMakeLists.txt`. Adding
`add_subdirectory(validation)` at the end of that file is equivalent; either
way the layers are also `ctest`s:

```bash
cd build/release-serial && ctest -R "layer1|layer2_4|layer3|layer5_loopback" --output-on-failure
```

- `layer1_golden` — layer 1. A failure is a transpilation bug in the algebra.
- `layer2_4_<model>` — layers 2 and 4 per model, in one binary. Whichever of
  the two has no sections in `references/<model>.txt` is skipped; with neither,
  the test reports SKIP (exit 77).
- `layer3_lv2` — layer 3 (lv2 only).
- `layer5_loopback_lv2` — the layer-5 binary with its optimiser answered by a
  built-in loopback (returns a fixed θ): the whole plumbing of the pipeline
  with a substituted optimiser, without MATLAB.

The exit code of a comparator is the number of failing comparisons. Every
MATLAB export is shape-checked before it is indexed, so a stale or truncated
reference fails with a message rather than reading past the end of a matrix.

## Full validation: layers 5 and 6

Layers 5 and 6 run the whole pipeline on both sides, so they need, on the same
machine as the C build: MATLAB R2024a or later with the Optimization Toolbox,
the CUQDyn1_Plus installation (`--matlab_repo=DIR`, always given, like
`--c_repo=DIR`), MEIGO64 (`--meigo=DIR`, `$MEIGO64_PATH`, or the copy under
`CUQDyn/Matlab/`), and a `python3` with numpy for the reports (`--python=EXE`).

```bash
C=$HOME/cuqdyn-c; M=$HOME/CUQDyn1_Plus
# a five-minute smoke run of the whole chain
validation/run_validation.sh layer 5 --c_repo=$C --matlab_repo=$M --problem=lv2 --budget=300
# the real thing, locally, one problem after another
validation/run_validation.sh layer 5 --c_repo=$C --matlab_repo=$M --problem=lv2,sir
validation/run_validation.sh layer 6 --c_repo=$C --matlab_repo=$M --problem=lv2 --seeds=10
# on a SLURM cluster: one job per problem, all at once
validation/run_validation.sh layer 5 --c_repo=$C --matlab_repo=$M --sbatch \
    --matlab_module=MATLAB/2024b --env=$HOME/cuqdyn-c-env.sh
validation/run_validation.sh layer 6 --c_repo=$C --matlab_repo=$M --sbatch \
    --matlab_module=MATLAB/2024b --env=$HOME/cuqdyn-c-env.sh
validation/run_validation.sh report --c_repo=$C
```

These are campaigns, not tests: at full budget lv2, ap and sir take 2-4 hours
per layer and nfkb about 12, which is why `--sbatch` exists. It submits the same
command once per problem (`tools/slurm_job.sh`; resources with
`--sbatch_opts="--time=... --mem=..."`). Layer 6 becomes an array with one MATLAB
seed per task, a job for the C seeds and a report job that waits for both;
finished seeds are skipped, so a campaign can be re-submitted.

**Layer 5** starts `pipeline_meigo` — the CLI with its optimiser swapped — has
MATLAB's MEIGO drive it (`meigo_server.m`) over a free local TCP port, then runs
the MATLAB pipeline copy with the same seeds (`run_pipeline_cvodes.m`) and writes
the report. Every launch k (0 = the full fit, then each leave-one-out refit in
order) is seeded `base_seed + k` on both sides, so a rounding flip in one launch
cannot contaminate the next. On the C side each `eval` goes through the
library's real `obj_func`; on the MATLAB side through the published
`prob_mod_cost_*`, both integrating with CVODES (BDF, dense, the XML
tolerances). The MATLAB copy computes its sensitivities with CVODES too
(`odeSensitivity`), like the C port; they agree with the layer-2 complex-step
references to ~1e-4 and reproduce the layer-4 delta bands to ~1e-5. MEIGO runs
with `dhc` as its local solver, the gradient-free solver the sacess configs use
(`tol 2`): `lsqnonlin`, the reference setting, works on the residual vector with
finite-difference Jacobians and turns a 1e-10 disagreement between the two
CVODES costs into a slow drift of θ that no eSS decision ever took, whereas
`dhc` only compares costs, so the two sides can part only on a discrete
decision. `CUQDYN_L5_LOCAL_SOLVER=lsqnonlin` restores the reference local solver.

**Layer 6** runs the production CLI (`SACESS_SEED=k`) and `CUQDyn1_Plus.m`
(`rng(k)`) N times each and compares the distributions. `--side=c`,
`--side=matlab` and `--side=report` run one half, for when the two sides live on
different machines: copy `results/layer6/<name>/` across and run the report.

Both layers take their budget from `<maxevaluation>` of the problem's
`sacess.xml` and hand the same number to MEIGO; the presets carry the budget
matched to MATLAB's (20000 evaluations for lv2, sir and nfkb, 10000 for ap),
not the smaller one of `example-files/`. `--budget=N` overrides it on both
sides at once.

## Where results go

Nothing a run writes is versioned. Everything lands under `--output_dir`
(default `validation/results/`, git-ignored):

| Command | Writes | What it is |
|---|---|---|
| `layer 1` | `layer1/report.txt` | per-check table of the kernels |
| `layer 2`, `layer 4` | `layer2_4/<name>/report.txt` | per-check table: trajectory, each dy/dθ block, bands, `Cov_p`, `std_y` |
| `layer 3` | `layer3/<name>/report.txt` | cost agreement over the recorded search |
| `layer 5` | `layer5/<name>/report.md` | per-launch lock-step table and final outputs |
| | `layer5/<name>/c/` | `cuqdyn-results.txt`, `run.log`, `meigo_server.log`, traces `evals_<k>.txt` / `theta_<k>.txt` |
| | `layer5/<name>/matlab/` | the layer-4 artefact set, `params_median.txt`, the same traces, `run.log` |
| `layer 6` | `layer6/<name>/report.md` (+ PNGs with matplotlib) | distributions side by side |
| | `layer6/<name>/c/seed_<k>/`, `matlab/seed_<k>/` | one full run per seed, with `timing.txt` |
| any `layer` | `<layer>/<name>/settings.txt` | the exact problem and run settings both sides used |
| `--sbatch` | `slurm/layer<N>_<name>_<job>.log` | the job logs |
| `report` | `REPORT.md` | the summary lines of every report found |
| `references` | **the repository**: `references/golden.txt`, `references/<name>.txt`, `references/<name>_evals.txt` | the versioned references; under `references/<name>/`: `settings.txt`, `check_problem.log` (do both sides define the same problem?) and the MATLAB logs |

## Adding a problem

A problem is one input directory, `--input=DIR`, holding everything the
validation needs; nothing in the harness knows the four models by name (the
presets are the directories of `input_validation/`).

| File | What |
|---|---|
| `cuqdyn.xml`, `sacess.xml`, `data.txt` | the C side: the three files the CLI takes (`-c`, `-s`, `-d`), copied from wherever they live (`example-files/<x>/`) |
| `problem.conf` | the MATLAB side: `matlab_problem=EXAMPLES/<X>`, a CUQDyn1_Plus problem directory (`define_problem_<X>.m`, `prob_mod_dynamics_<X>.m`, `prob_mod_cost_<X>.m` and its data folder, see `EXAMPLES/problem_definition_template.m`) relative to `--matlab_repo` or absolute, plus `matlab_problem_name=X` if the directory holds several definitions |

The directory's name names the references and the outputs. `--c_repo=` and
`--matlab_repo=` say where the two installations are, as always.

1. **Check that both sides describe the same problem.** `references` does it
   before freezing anything, and the layer-5 smoke run below exercises it too:
   `matlab/check_problem.m` compares what is defined twice — number of states
   and parameters, time grid, initial condition, observed states, bounds,
   initial point and residual model. A mismatch is an error: fix the XML or the
   definition. What is only a run setting comes from the C files and is handed
   to MATLAB, so the two sides cannot drift: α, the integration tolerances, the
   eSS budget, and a known σ (MATLAB derives σ from the reference trajectory by
   a convention the example runners do not all share — `define_problem_SIR.m`
   averages over all times, `run_SIR_CUQDyn1Plus.m` over t > 0 — so the check
   only warns when the derivation and the XML differ).

1. **Smoke-test the end-to-end layers**: `layer 5 --input=DIR --budget=300`,
   then `layer 6 --input=DIR --seeds=2 --budget=300` (with `--c_repo` and
   `--matlab_repo`). They need no references.

1. **Generate the references of layers 2-4** (MATLAB; layer 4 is one full
   CUQDyn1_Plus run): `references --input=DIR`. It writes
   `references/<name>.txt` and adds a `[<name>]` section to
   `references/tolerances.txt` with the tolerances of a well-conditioned model;
   loosen them by hand if the problem is stiff or its FIM ill-conditioned (next
   section). `RECORD_LAYER3=1` also records a search for layer 3. Commit them.

1. **Make it a preset** so that `--problem=<name>` and `--problem=all` include
   it: move the directory to `input_validation/<name>/` and add the name to the
   `foreach(model ...)` of `CMakeLists.txt` so that layers 2 and 4 run under
   `ctest`.

If the C side uses a compiled Rust model, check its parameter order against
`prob_mod_dynamics_<X>.m` first: layer 2 fails on exactly that (see the warning
about `lotka-volterra` below).

## Regenerating the references (MATLAB only)

The references of layers 1-4 are versioned so that those layers run anywhere;
they are regenerated by script, never edited:

```bash
C=$HOME/cuqdyn-c; M=$HOME/CUQDyn1_Plus
validation/run_validation.sh references --c_repo=$C --matlab_repo=$M                # the four presets
validation/run_validation.sh references --c_repo=$C --matlab_repo=$M --problem=lv2  # one of them
validation/run_validation.sh references --c_repo=$C --matlab_repo=$M --part=layer1  # layer 1 only
git status --short validation                                                       # what changed
```

`references` regenerates, per problem, layers 2 and 4 together (and layer 3
where a recorded search exists, or with `RECORD_LAYER3=1`); `--part=layer1`
regenerates the golden vectors alone. It always uses the CUQDyn1_Plus given by
`--matlab_repo`, never a copy vendored in the C repository.

Only needed when the MATLAB reference itself changes, or to check that your
MATLAB reproduces them: layers 1 and 2 are deterministic (expect differences at
the last digits across MATLAB releases); layers 3 and 4 are seeded MEIGO runs
(seeds 20260828 and 20260819), repeatable on one MATLAB release. nfkb's layer 4
takes about two hours. `tolerances.txt` is never overwritten.

The MATLAB entry points are `matlab/gen_golden.m` (no problem involved),
`matlab/gen_baseline.m` (layers 2, 4 and the MATLAB side of 6) and
`matlab/gen_cost_replay.m`; the last two take the `settings.txt` that
`run_validation.sh` writes, which is how they learn where the problem lives.

Provenance of the current references: regenerated with
`run_validation.sh references --sbatch` on drago.csic.es, MATLAB R2024b
(the `[meta]` section of `references/<name>.txt` records the release).

## Tolerances and how to read a failure

Per model, one `[<model>]` section of `references/tolerances.txt` (maintained
by hand; `references` adds a section for a new problem with the lv2 values and
never overwrites one):

| Key | lv2 / sir | ap | nfkb | Why |
|---|---|---|---|---|
| `layer2_traj` | 1e-4 | 5e-4 | 5e-4 | both integrate at RelTol 1e-6; two correct solvers agree to that order (ap has a long horizon with tiny rate constants) |
| `layer2_sens` | 5e-3 | 1e-2 | 1e-2 | complex step is exact, CVODES sensitivities carry their own integration error |
| `layer4_conformal` | 1e-9 | 1e-9 | 1e-9 | identical inputs and the same quantile algorithm: more than this is a bug |
| `layer4_delta` | 1e-2 | 5e-2 | 1e-1 | inherits the sensitivity error through the inverse of the FIM |
| `layer4_covp` | (= delta) | (= delta) | 1e3 | at cond(FIM) ~ 3e8 the element-wise covariance is regularisation-dominated on both sides; the bands and `std_y` are the meaningful comparison |
| `layer5_cost` | 1e-4 | 1e-4 | 1e-3 | how far the two CVODES builds may disagree on J at the same θ in the lock-step check. Measured over 463 024 identical evaluations of lv2: 5e-9 in the median and below 1e-6 for 99.996% of them; on the remaining 19, where the two integrators take a different step sequence, they differ at the integration tolerance (up to 3.4e-5, never beyond 1e-4). The stiff nfkb reaches 3e-4 (its trajectories already differ by 5e-4, `layer2_traj`). A wrong data slice moves J by ~1/m, orders of magnitude more |

Layer 1 uses 1e-9 relative, scaled by the largest magnitude of the expected
array. One case carries its own tolerance derived from theory:
`fim_04_rank_deficient` builds an exactly singular J where only the ridge
(2e-10) makes J'J invertible; at cond = 1e12, LAPACK and GSL cannot agree
better than eps·cond ≈ 2e-4, so its tolerance is 1e-3. The lesson belongs to
the method: with a near-singular FIM the numerical covariance is
regularisation-dependent in any implementation, which is why `delta_bands.c`
prints the rank and condition number.

Layer 5 reads the two evaluation traces of each launch: "the same evaluation"
is θ within 1e-12 relative, "the same cost" J within `layer5_cost` of `tolerances.txt`, "the same optimum"
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
Rust model swaps p3 and p4 with respect to `prob_mod_dynamics_LV.m`.
`input_validation/lv2/` is a copy of `example-files/lv2-partobs/`, which
defines the ODE by expressions and does match. The compiled `nfkb` model is verified term by term.

## Reproducibility

Every run is one `run_validation.sh` command line, and it leaves next to its
results what is needed to launch it again: `run_info.txt` (the command line,
the commit, the MATLAB executable, host, date, seeds) and `settings.txt` (the
problem and the run settings exactly as both sides used them).

What was measured on drago (MATLAB R2024b, 2026-09-21):

- **The same command twice gives the same bytes.** Layer 5 (lv2) and layer 6
  (sir, two seeds per side), each run twice with identical options: every
  result file identical (about 160: C results, MATLAB results and the 62
  evaluation traces). Only logs and `timing.txt` differ.
- **The references regenerate.** `references` on another MATLAB release and
  operating system (R2024b on Linux, against the committed R2024a on Windows):
  layer 2 byte-identical; layer 4 within 6e-6 on ap and sir (bands to 3e-6,
  theta_hat to 1e-10) and 2e-4 on lv2 (individual LOO trajectories; its bands
  to 2e-6). On nfkb the seeded layer-4 run lands in another basin of its
  non-identifiable landscape on the other release (theta_hat 3% apart, bands
  13%), which layer 4 does not mind: it replays whatever ensemble MATLAB
  produced. The C harness passes against either set, 71/71. Layer 1 differs in
  the last digit, and in the sign of the input of `fim_07`, which comes out of
  `qr`; layer 3 records a search of a different length. Both are expected
  across releases: inputs and expected outputs are regenerated together.

How it is obtained:

- MATLAB: `rng(seed, 'twister')` and a SEQUENTIAL LOO loop
  (`use_parallel = false`; with `parfor` the stream is split across workers and
  is not repeatable). Layer 3 uses the fixed seed 20260828, layer 4 the fixed
  seed 20260819, layer 6 the seeds 1..N.
- Layer 5: base seed 20260917 (`--base_seed`); launch k is seeded
  `base_seed + k` on both sides, immediately before MEIGO starts.
- C: `SACESS_SEED=<k>` (set by `run_validation.sh layer 6`).
- Seeds on one side do not correspond to seeds on the other in layer 6, which
  is why it compares distributions.
- Optimiser budgets, α, the integration tolerances and a known σ cannot differ
  between sides: MATLAB takes them from the XML files the C side runs with
  (`tools/problem_info.py` → `settings.txt` → `matlab/load_problem.m`).
- Bit-for-bit repeatability holds on one machine, MATLAB release and build. A
  different MATLAB release, BLAS or compiler changes the last digits, and eSS
  amplifies that into a different search after some hundreds of evaluations;
  what is then reproducible is the verdict of each layer, not the bytes.

## The shared-optimiser experiment (`matlab/hybrid_meigo_cvodes.m`, `c/cost_server.c`)

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
Its reports (`results/hybrid/hybrid_report_<model>.txt`) are run outputs like
every other and stay on the machine that produced them.

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
  deterministic check of the same pipeline.
- **Local solver.** MEIGO uses `lsqnonlin`, the sacess configs use `dhc`. Both
  search in log scale. This is a legitimate difference between two optimisers
  and belongs to what layer 6 measures; layer 5 removes it by using MEIGO on
  both sides, with `dhc` (see above).
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
