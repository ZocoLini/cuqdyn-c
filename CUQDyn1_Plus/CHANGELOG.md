# Changelog

## [2026-07-14]

### Improvements

- **End-to-end manuscript pipeline runner**: added `scripts/run_full_evaluation.m`,
  an unattended `matlab -batch` runner that chains the seven regeneration stages
  (`validate`, `examples`, `tutorial`, `sbc`, `pymc`, `compare`, `reports`) with
  per-stage timing, diary logging under `scripts/eval_logs/<timestamp>/`, and an
  `evaluation_summary.csv`. Consumer stages are skipped rather than run on stale
  outputs when a prerequisite fails; the full SBC stage prints a runtime warning;
  and `reports` is skipped under `UseFastSBC` unless `AllowFastReports` is set.
- **Ignore batch-runner logs**: added `scripts/eval_logs/` (and stray PyTensor
  compile caches) to `.gitignore`.

## [Unreleased — Future Work]

- Rename `fast_compute_hybrid_uncertainty.m` (FIM-only helper) to reduce
  developer confusion (currently named "hybrid" but is FIM-only).
- Add a real-data onboarding example with no known hidden true trajectory,
  making the `docs/tutorialProblemDef.md` workflow more concrete for new users.

## [2026-07-13]

### Improvements

- **Repository documentation cleanup**: moved supporting notes and reports into
  `docs/` and `REPORTS/`, refreshed README file inventories, documented the
  root-level entry point scripts, and removed stale local-only files including
  `.claude/`.
- **Master-run reproducibility metadata**: `run_all_examples.m` now records the
  machine, operating system, MATLAB version, and processor information used for
  benchmark runs.
- **SBC batch automation**: added `scripts/run_sbc_evaluation.m`, a guarded
  MATLAB batch runner for the maintained SBC calibration scripts.
- **PyMC comparison diagnostics and reports**: tightened the PyMC documentation,
  added NF-kB convergence caveats and diagnostic reporting, and refreshed the
  CUQDyn-versus-PyMC report-generation workflow.
- **Generated artifact hygiene**: updated `.gitignore` rules for PyTensor,
  MATLAB autosaves, and editor backups, and removed stale tracked NF-kB helper
  scaffolding.

## [2026-07-08]

### Improvements

- **FIM covariance conditioning diagnostics**: added a shared
  `cuqdyn_fim_covariance` helper used by both CUQDyn1_Plus and HybridCov.
  FIM rank and conditioning are now diagnosed from an SVD of the residual
  Jacobian in log-parameter space by default, while the returned `Cov_p`
  remains in natural parameter units for existing confidence intervals and
  trajectory propagation.
- **Weak-direction reliability flags**: FIM diagnostics now include
  normalized weak-direction sensitivity by state/time so bands affected by
  poorly identified directions can be marked unreliable instead of silently
  interpreted as well conditioned. `diagnose_uq_quality` reports the stored
  FIM rank, condition number, weak-direction count, and reliability summary.

## [2026-05-29]

### Improvements

- **Example method notes**: added `METHOD_NOTES.md` files for AP, LV, SIR,
  NF-kB, and LinearCascade. Each note records the observed-state pattern,
  residual scaling, parameter bounds, and intended UQ workflow for the example.
- **Problem-definition observability cleanup**: aligned AP, LV, and NF-kB
  `define_problem_*` metadata with the CSV files used by the maintained
  CUQDyn1_Plus scripts. AP now declares states 1-4 observed and state 5 hidden;
  LV and NF-kB now include explicit top-level `observed_state_indices`.
- **Lightweight validation script**: added `validate_cuqdyn_repo.m`, a fast
  local/CI-style health check for path setup, selected Code Analyzer checks,
  problem definitions, CSV observability, generated-module equivalence, and a
  tiny generated LV data/cost smoke test.
- **Master-run documentation**: added `README_run_all_examples.md` describing
  the purpose, outputs, warning capture, and interpretation of
  `run_all_examples.m`.
- **License consistency**: added a GPLv3 `LICENSE` file and updated README
  license text from the stale header to GPLv3.

### Calibration notes

- Larger shared-fit/fast SBC calibration runs were completed for the maintained
  LV, SIR, AP, and LinearCascade3 workflows. The result folders remain local
  generated outputs and are intentionally not tracked by Git.
- LinearCascade3 remained under-covered despite being dynamically simple,
  indicating that downstream-only observation of `x3` is a hidden-state
  uncertainty stress test for upstream states rather than a trivial calibration
  case.

## [2026-05-22]

### New features

- **High-level problem definitions**: added `define_problem_<Example>.m` files for LV, SIR, AP, NFKB, LinearCascade, and LinearCascade3. These declare states, parameters, ODE right-hand sides, fitting metadata, data metadata, and residual-normalization settings in a single problem struct.
- **Problem module generator/validator**: added `cuqdyn_validate_problem`, `cuqdyn_generate_problem_files`, and `cuqdyn_check_generated_problem_modules`. The generator writes legacy-compatible `prob_mod_dynamics_<Name>.m` and `prob_mod_cost_<Name>.m` files so existing CUQDyn run scripts can continue using function handles without algorithm changes.
- **Problem-definition cheatsheet**: added `EXAMPLES/problem_definition_template.m`, a copyable MATLAB template documenting the problem schema and the supported residual-normalization declarations.
- **Problem-level cost option helper**: added `cuqdyn_cost_options_from_problem`, which converts `problem.cost` declarations into `cost_opts`, including explicit known sigmas, synthetic-data sigmas computed from a reference trajectory, and manual per-observed-state weights.
- **Problem-driven synthetic data generation**: added `cuqdyn_generate_synthetic_data` and `cuqdyn_generate_data_script`. Problem definitions can now declare `problem.synthetic_data` so users can generate both the legacy model files and a readable CUQDyn-formatted data-generation script from the same high-level definition.
- **Generated-module equivalence checker**: added `EXAMPLES/check_generated_problem_definitions.m`, which regenerates each maintained example's problem modules in temporary folders and verifies that generated dynamics/cost outputs match the legacy files. Per-example `generated_problem/` folders are disposable local outputs; a small LV generated snapshot is kept under `EXAMPLES/generated_reference/LV/` for inspection.
- **`src/save_trajectory_nrmse_tables.m`** — post-fit trajectory error reporting for CUQDyn1 results. Writes compact Excel sheets for data availability, RMSE/MAE/NRMSE, UQ coverage, interval width, and pointwise residuals.
- **`src/diagnose_uq_quality.m`** — independent post-fit UQ diagnostics for both CUQDyn1_Plus and CUQDyn1_Plus_HybridCov. Reports covariance conditioning/eigenvalues, residual variance estimates with and without the initial condition, parameter standard deviations, correlations, and optional near-bound flags.
- **`src/bootstrap_trajectory_uq.m`** — optional parametric bootstrap trajectory uncertainty. Simulates observed bootstrap datasets around the fitted trajectory, refits parameters, propagates trajectories, and returns empirical quantile bands.
- **`EXAMPLES/LV/SBC_LV2_FIM_vs_HybridCov_sharedfit.m`** — shared-fit calibration script comparing FIM and HybridCov bands from the same optimizer solution, LOO ensemble, residual variance, and sensitivity linearization.
- **`tutorialUQ.md`** — written LV walkthrough summarizing the three prediction-UQ workflows, expected outputs, metric interpretation, and how to generalize the table calls to other examples.
- **`tutorialProblemDef.md`** — problem-definition tutorial covering high-level model schemas, generated dynamics/cost files, residual normalization, synthetic data generation, and starter run setup.
- **Central run options helpers**: `cuqdyn_default_options`, `cuqdyn_fill_meigo_options`, `cuqdyn_set_ode_options`, `cuqdyn_get_ode_options`, and `save_run_options` centralize optimizer/UQ/ODE defaults and save the effective settings with each run.
- **Known-sigma residual weighting**: cost functions, MEIGO fits, and FIM covariance can now use standardized residuals through `opts.cost.residual_model = 'known_sigma'`. Synthetic LV/SIR/NFKB and SBC scripts use the noise standard deviations implied by their data-generation models.
- **Experimental guarded local LOO refits**: `opts.meigo.refit.strategy = 'local_after_global'` keeps the initial full-data eSS fit but uses `lsqnonlin` for repeated LOO fits, with automatic eSS fallback when local diagnostics fail. The default remains eSS everywhere (`'global'`) while examples are compared.
- **Fast SBC comparison scripts**: added `_fast` variants for LinearCascade3, LV, SIR, and AP SBC scripts using `local_after_global` LOO refits so runtime and calibration can be compared directly against the eSS-everywhere baselines.
- **`EXAMPLES/LinearCascade/diagnose_LinearCascade_known_truth.m`** — analytic two-state linear cascade diagnostic for checking weighted residuals, FIM covariance, and hidden-state delta-method standard deviations against an independent analytic-solution reference.
- **`EXAMPLES/LinearCascade/diagnose_LinearCascade3_known_truth.m`** — three-state linear cascade stress test observing only the downstream state. Uses an independent matrix-exponential reference to verify covariance and hidden-state standard deviations.
- **`EXAMPLES/LinearCascade/SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit.m`** — repeated-simulation calibration for LinearCascade3 hidden-state coverage, comparing FIM and HybridCov bands from the same fit per replicate.
- **`run_all_examples.m`** — master non-SBC example-suite runner. Executes LV, SIR, AP, NFKB, and LinearCascade examples across their available CUQDyn methods, catches per-script errors, performs basic sanity checks on generated result structs, and writes summary workbooks plus per-example logs.
- **New unit tests** for trajectory NRMSE tables, UQ diagnostics, and bootstrap trajectory UQ.

### Improvements

- **Portable path setup** in `setPath_CUQDyn1_Plus.m`: removes the hard-coded local MEIGO path and supports either repo-local `MEIGO64-master/` or `MEIGO64_PATH`.
- **MEIGO kept local by default**: `MEIGO64-master/` is ignored by Git.
- **README refreshed** for v22May26, `unitTests/`, NFKB example contents, lowercase data folders, and non-bundled MEIGO setup.
- **Example reporting expanded** with trajectory NRMSE table calls across LV/AP/SIR examples.
- **LV three-method tutorial settings updated** to use a more informative bootstrap run (`n_boot = 50`) and higher MEIGO evaluation budget (`maxeval = 1500`) by default.
- **Example option handling standardized** so LV/AP/SIR/NFKB examples and SBC scripts build defaults, apply local overrides, set shared ODE tolerances, and pass effective MEIGO options explicitly. The AP scripts now pass the MEIGO settings they define.
- **FIM covariance now follows the selected cost model**, so weighted fits and uncertainty calculations stay statistically consistent.
- **Example workflow consistency pass**: LV/AP/SIR/NFKB scripts now consistently read pre-existing CSV data at the start of the workflow, create timestamped result folders after data loading, and pass detailed Excel export arguments in the same order.
- **Master example runner fix**: corrected `run_all_examples.m` manifest path construction so scripts are resolved as files rather than duplicated as `script.m/script.m`, and removed the duplicate legacy NF-kB entry from the non-SBC master run.
- **Repository cleanup**: removed tracked generated result folders, SBC temporary outputs, `ess_report.mat` files, MATLAB diary output, and the local PyTensor cache from version control. Added ignore rules so new generated run outputs stay local.
- **PyMC/MATLAB Bayesian comparison cleanup**: renamed `ABCSMC_pymc_matlab/` to `pymc_matlab/`, kept only the maintained LV/SIR/AP/NF-kB comparison workflows, removed obsolete standalone Lotka/SEIR demo scripts and local demo CSVs, and documented that each maintained script reads the same CSV used by the corresponding CUQDyn example.
- **Shared CUQDyn-vs-PyMC comparison summaries**: added `pymc_matlab/compare_cuqdyn_pymc.m`, which reads completed PyMC CSV exports and the latest CUQDyn result folders for LV/SIR/AP/NF-kB, then writes unified parameter summaries, trajectory-band summaries, and method overlay plots under `pymc_matlab/results/comparison/`.
- **PyMC comparison settings tightened**: PyMC scripts now export 500 trajectory samples, use noise-augmented predictive trajectories for observed-state coverage, preserve latent `*_latent_trajectories.csv` exports, tighten LV/SIR ODE tolerances, increase SIR/AP/NF-kB SMC draws to 1000 per chain, and align AP priors with the current widened CUQDyn AP bounds.
- **Synthetic-data generation consistency**: each example now has a canonical `data_generation/generateSyntheticData_<Example>.m` script that writes CUQDyn-formatted CSVs into the example `data/` folder. Legacy nested AP/LV generator entry points are retained as wrappers, and generated CSV copies inside `data_generation/` are no longer tracked.
- **Synthetic-data positivity checks**: generators now validate that finite generated data contain no negative values and expose `min_observed_value` to floor noisy observed measurements after `t=0` while preserving exact zero initial conditions by default.
- **Bundled data positivity audit**: verified that all example CSVs used from `EXAMPLES/*/data/` contain no negative finite values; minima are zero where exact initial conditions or zero-valued states are expected.

### Calibration notes

- Shared-fit LV calibration (`n=50`, nominal 95%) produced similar pointwise coverage for FIM and HybridCov: FIM 92.9%, HybridCov 92.8%. This suggests that, for this LV setup, replacing FIM correlations with LOO correlations does not materially improve unobserved predator coverage once both methods share the same fitted trajectory and LOO ensemble.
- LinearCascade3 shared-fit calibration (`n=20`, nominal 95%) produced nearly identical coverage for global and local-after-global LOO refits. The local-after-global variant reduced runtime from about 19.4 min to 13.0 min, with 700/700 local LOO refits and no fallback calls.

---

## [2026-05-17]

### Bug fixes

- **LV HybridCov using wrong dataset** (`EXAMPLES/LV/run_LV2_CUQDyn1_Plus_HybridCov_partobs_example.m`): the script was generating its own synthetic data (`DATA_LV2/lv2_partobs.csv`) instead of reading the shared pre-existing dataset. Removed the inline data-generation block and aligned it with the other two LV scripts (`data/lv2_synthetic_data_noi10_partobs_1.csv`). All three LV scripts (partobs, HybridCov, Bayesian) now operate on identical observations.
- **`lv_pymc.py` execution-order bug**: the posterior predictive plot referenced `prey_mat`/`pred_mat` before they were built. Moved the trajectory-ensemble construction to immediately after the mean-trajectory computation so variables are defined before use.
- **Unicode encoding error on Windows** (`lv_pymc.py`, `sir_pymc.py`): `σ` (U+03C3) in diagnostic print statements caused `UnicodeEncodeError` on cp1252 consoles. Replaced with the ASCII string `sigma`.
- **Narrow inner LOO band removed from `plot_hybrid_uq`**: the 50% PI derived from the LOO trajectory ensemble (`media_matrix`) was near-zero width because leave-one-out fits barely change for well-determined problems. The band was misleading; only the conformal outer PI is now shown.

### New features

- **`unitTests/test_plotting_functions.m`** — 21-test MATLAB unit test class covering:
  - `savefig_png`: file creation, MATLAB `string` vs `char` path, default 150 DPI, custom DPI, `sgtitle`+subplots crash regression.
  - `plot_hybrid_uq`: single-state, LV (2-state), SIR (3-state), AP (5-state), negative-`UQ_lower` clamping, `string` `resultDir`, 95% CI variant, successive calls without crash.
  - `print_param_recovery`: basic, HybridCov auto-detection, default `alp`, single parameter, 5-parameter AP, perfect recovery, 95%/90% variants, HybridCov 5-parameter.

### Improvements

- **`plot_hybrid_uq.m` rewritten** with a cleaner single-band style: conformal PI shaded region (`FaceAlpha` 0.25), solid best-fit line for observed states, dashed for unobserved, data markers with white fill. Uses MATLAB default colour order per state. Removes dependency on `media_matrix`.
- **All 9 example scripts confirmed to use the three shared utility functions** (`plot_hybrid_uq`, `savefig_png`, `print_param_recovery`); no inline save or recovery code remains in any script.
- **Three SBC scripts migrated from `saveas` to `savefig_png`** (`SBC_LV2_FIM_vs_HybridCov.m`, `SBC_SIR_FIM_vs_HybridCov.m`, `SBC_AP_FIM_vs_HybridCov.m`, 19 call sites total), eliminating `SubplotListenersManager` crash risk in those scripts.

---

## [2026-05-16]

### Bug fixes

- **`SubplotListenersManager/enable` crash** in all scripts that call `sgtitle` or `linkaxes` and then save figures: `saveas` → `print` → `alternatePrintPath` triggered subplot listeners in an invalid state in interactive MATLAB sessions.
  - Root cause isolated via MCP testing: (1) `savefig` before `exportgraphics` invalidates `sgtitle`/`linkaxes` handles; (2) the first iteration's `linkaxes` listeners remain active while the second iteration's figure is being saved.
  - Fix: new `savefig_png` utility calls `exportgraphics` first, then `savefig`, and all diagnostic loops close the figure at the end of each iteration (`close(fig_c)`).
- **`[base_path '.fig']` string-type error** in `savefig_png`: `fullfile` returned a MATLAB `string` object when `resultDir` used double-quote syntax; `[]` concatenation then created a 1×2 string array instead of a char vector. Fixed with `base_path = char(base_path)` at the top of the function.
- **`Y_true` cleared-variable error** in `run_SIR_CUQDyn1Plus_HybridCov.m`: section 2 was replaced with CSV loading (removing data generation), but diagnostic figure code still referenced `Y_true`. Fixed by recomputing `Y_true` via `ode15s` with true parameters before the diagnostic section.
- **Missing `addpath`** in `run_LV2_CUQDyn1_Plus_partobs_example.m` and both AP example scripts, causing `loadStateData is not found` when run via MCP. Added `addpath(genpath('../../'))` to all three.
- **Misleading ABC-SMC posterior predictive coverage warning** in all three Python Bayesian scripts: the 95% PI captured only parameter uncertainty, not observation noise, so coverage against noisy data was reported as ~48% even for a well-fitting model. Fixed by estimating observation noise as the RMSE of the posterior mean trajectory, adding `N(0, σ_est)` to each predictive trajectory before computing the PI, and reporting the augmented coverage with a clear diagnostic label.

### New features

- **`src/print_param_recovery.m`** — reusable parameter recovery summary function callable from all CUQDyn1Plus example scripts. Prints a table of true value, estimate, CI bounds, relative error, and in-CI flag for each parameter. Auto-detects HybridCov results via `isfield(results, 'D_fim')` and adds FIM/LOO/Hybrid marginal std dev comparison columns when present. Prints the full covariance matrix. Accepts optional `alp` argument (defaults to 0.05).
- **`src/savefig_png.m`** — crash-safe figure saver. Uses `exportgraphics` (R2020a+) instead of `saveas`/`print`, saving both `.png` and `.fig`. Accepts both `char` and MATLAB `string` path arguments.

### Improvements

- **Dual quantile band posterior predictive plots** in all three Python Bayesian scripts (`lv_pymc.py`, `sir_pymc.py`, `ap_pymc.py`): replaced spaghetti trajectory plots with shaded 95% PI (outer, `alpha=0.20`) and 50% PI (inner, `alpha=0.45`) bands computed from a 75-sample trajectory ensemble, plus a solid posterior-mean line and data markers. The trajectory ensemble is now built once and reused for both the plot and CSV export, eliminating redundant ODE solves.
- **`print_param_recovery` added to all six CUQDyn1Plus example scripts**: `run_LV2_CUQDyn1_Plus_partobs_example.m`, `run_LV2_CUQDyn1_Plus_HybridCov_partobs_example.m`, `run_AP_CUQDyn1Plus_partobs_example.m`, `run_AP_CUQDyn1Plus_HybridCov_partobs_example.m`, `run_SIR_CUQDyn1Plus.m`, `run_SIR_CUQDyn1Plus_HybridCov.m`.
- **`savefig_png` adopted in all six CUQDyn1Plus example scripts and three SBC scripts**, replacing all `saveas`, `drawnow+print`, and inline `print` calls.
- **`plot_hybrid_uq` called from all six CUQDyn1Plus example scripts**, replacing per-script inline plotting loops.
