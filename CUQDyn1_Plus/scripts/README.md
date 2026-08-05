# Auxiliary scripts

This folder contains supporting automation rather than the main user-facing
entry points. `run_all_examples.m` and `validate_cuqdyn_repo.m` intentionally
remain at the repository root.

## Full manuscript pipeline runner

`run_full_evaluation.m` orchestrates the entire figure/table regeneration
sequence from `how_to_generate_figures_tables.md` as a single unattended
`matlab -batch` job: `validate`, `examples`, `tutorial`, `sbc`, `pymc`,
`compare`, and `reports`. Each stage is isolated in a `try`/`catch`, timed, and
diary-logged under `scripts/eval_logs/<timestamp>/`, with a per-stage
`evaluation_summary.csv` written at the end. Robust launch (folder-independent):

```powershell
matlab -batch "addpath(genpath('<repo>')); run_full_evaluation"
```

A `matlab -batch` process inherits environment variables from the shell that
launches it, so `$env:MEIGO64_PATH` set in the same session is visible. The trap
is a value set only in a different shell/session (or never set/persisted), which
MATLAB will not see. Set it in the launching session, or pass `MeigoPath` (the
repo still needs to be on the path):

```powershell
matlab -batch "addpath(genpath('<repo>')); run_full_evaluation('MeigoPath','<meigo>\MEIGO64-master')"
```

Notes:

- With `ContinueOnError=true` (default) a failed producer stage does **not**
  let `compare`/`reports` run on stale outputs — dependent stages are marked
  `SKIPPED` instead (see the file header for the dependency map).
- The full `sbc` stage (`UseFastSBC=false`, default, for manuscript-grade
  evidence) can take **many hours**; the runner prints a loud warning first.
- `UseFastSBC=true` produces non-standard SBC folder names, so `reports` is
  skipped unless `AllowFastReports=true` is also passed.
- `run_full_evaluation('list')` prints the ordered stage names and exits.

### Explorer / PowerShell launch wrapper

`run_evaluation.bat` wraps the full pipeline for a double-click launch from
Windows Explorer. Edit the three paths at the top of the file, then:

```
scripts\run_evaluation.bat                   # From repo root, in cmd or PowerShell
Start-Process scripts\run_evaluation.bat     # Opens in its own window; returns immediately
```

You can close PowerShell after `Start-Process` — the `.bat` window stays open
until the pipeline finishes, and the runner writes logs to `eval_logs/` regardless.

## SBC batch runner

`run_sbc_evaluation.m` runs the maintained SBC calibration scripts with guarded
path setup and per-script cleanup. From MATLAB:

```matlab
cd('<repo root>')
addpath(genpath(pwd))
run_sbc_evaluation
```

or call it with an explicit repository path:

```matlab
run_sbc_evaluation('<repo root>')
```

## Python report generators

The Python report generators are intended to be run with the Python environment
declared in `pymc_matlab/pyproject.toml`. From the repository root, use the PyMC
uv environment, for example:

```powershell
cd pymc_matlab
uv run python ..\scripts\generate_results_latex_report.py
uv run python ..\scripts\generate_cuqdyn_pymc_comparison_report.py
uv run python ..\scripts\generate_combined_tutorial_latex.py
```

For the full manuscript regeneration sequence, including CUQDyn examples, PyMC
runs, comparison tables, and dated `REPORTS/` folders, see
`how_to_generate_figures_tables.md`.
