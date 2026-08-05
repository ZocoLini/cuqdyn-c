# Regenerating CUQDyn1plus Manuscript Figures And Tables

This checklist regenerates the CUQDyn1plus result folders, figures, Excel tables, and LaTeX report snippets used by the manuscript. Replace placeholders before running:

- `<repo>`: local clone of `CUQDyn1_Plus`
- `<MEIGO>`: local `MEIGO64-master` folder

Run MATLAB in light theme if the figures will be used directly in the manuscript.

## 0. Automated Full Pipeline

For a single unattended run, use the batch runner:

```powershell
matlab -batch "addpath(genpath('<repo>')); run_full_evaluation"
```

If MEIGO is not available through `MEIGO64_PATH` or `<repo>\MEIGO64-master`,
pass it explicitly:

```powershell
matlab -batch "addpath(genpath('<repo>')); run_full_evaluation('MeigoPath','<MEIGO>')"
```

The runner executes stages 1-7 below (`validate`, `examples`, `tutorial`, `sbc`,
`pymc`, `compare`, and `reports`) with per-stage timing and diary logging under:

```text
<repo>\scripts\eval_logs\<timestamp>\
```

It skips dependent consumer stages rather than allowing `compare` or `reports`
to run on stale outputs after a producer-stage failure. The full `sbc` stage is
intended for manuscript-grade regeneration and can take many hours; for quick
development checks, use:

```powershell
matlab -batch "addpath(genpath('<repo>')); run_full_evaluation('UseFastSBC', true)"
```

When `UseFastSBC=true`, the `reports` stage is skipped by default because the
fast SBC folders do not use the standard folder prefixes expected by the report
generators.

Use the manual steps below when you want to rerun only part of the pipeline or
inspect each stage interactively.

## 1. MATLAB Setup

Run from MATLAB:

```matlab
cd('<repo>')
addpath(genpath(pwd))
addpath(genpath('<MEIGO>'))
```

Optional quick validation:

```matlab
summary = validate_cuqdyn_repo();
```

## 2. Main Non-SBC CUQDyn Results

Run from the repository root in MATLAB:

```matlab
summary = run_all_examples();
```

This regenerates the maintained non-SBC examples:

- LV FIM and HybridCov
- SIR FIM and HybridCov
- AP FIM and HybridCov
- NF-kB FIM and HybridCov
- LinearCascade and LinearCascade3 known-truth diagnostics

Each run creates timestamped result folders under `EXAMPLES/<model>/`. The master runner also writes `EXAMPLES/Master_Run_Results_<timestamp>/` with logs, summary workbooks, and `machine_info.*` files.

Figures saved through `savefig_png` are written as `.fig`, `.png`, `.pdf`, and `.eps`.

## 3. LV Three-Method Tutorial

`run_all_examples` does not run the LV bootstrap/tutorial comparison. Run it separately:

```matlab
cd('<repo>\EXAMPLES\LV')
tutorial_LV_three_prediction_UQ_methods
```

This creates:

```text
EXAMPLES\LV\Tutorial_LV_three_UQ_methods_<timestamp>\
```

Key outputs include:

- `lv_predator_three_uq_methods.*`
- `three_uq_methods_metric_comparison.xlsx`
- FIM, HybridCov, and bootstrap subfolders

## 4. SBC Calibration Results Used By The Report

The main report generator expects the latest available SBC folders for LV, SIR, AP, and LinearCascade3. Run these in MATLAB:

```matlab
cd('<repo>\EXAMPLES\LV')
SBC_LV2_FIM_vs_HybridCov_sharedfit

cd('<repo>\EXAMPLES\SIR')
SBC_SIR_FIM_vs_HybridCov

cd('<repo>\EXAMPLES\AP')
SBC_AP_FIM_vs_HybridCov

cd('<repo>\EXAMPLES\LinearCascade')
SBC_LinearCascade3_FIM_vs_HybridCov_sharedfit
```

These scripts can be slow. For quick development checks, the `_fast` variants exist, but the manuscript report generator currently looks for the standard folder prefixes used by the scripts above.

## 5. PyMC Environment And Inference Runs

From PowerShell:

```powershell
cd <repo>\pymc_matlab
uv sync
uv run python -m py_compile lv_pymc.py sir_pymc.py ap_pymc.py nfkb_pymc.py pymc_export_utils.py
```

Then run the PyMC ABC-SMC workflows:

```powershell
uv run python lv_pymc.py
uv run python sir_pymc.py
uv run python ap_pymc.py
uv run python nfkb_pymc.py
```

Default output folders:

```text
pymc_matlab\results\lv\
pymc_matlab\results\sir\
pymc_matlab\results\ap\
pymc_matlab\results\nfkb\
```

Optional NF-kB 4000-draw sensitivity run, kept separate from the baseline 1000-draw comparison folder:

```powershell
$env:NFKB_PYMC_DRAWS="4000"
$env:NFKB_PYMC_RESULTS_DIR="results/nfkb_4000"
uv run python nfkb_pymc.py
Remove-Item Env:NFKB_PYMC_DRAWS
Remove-Item Env:NFKB_PYMC_RESULTS_DIR
```

If PyTensor compilation fails on Windows, use a writable cache:

```powershell
$env:PYTENSOR_FLAGS="base_compiledir=$env:TEMP\pytensor_cache"
```

## 6. CUQDyn-vs-PyMC Comparison Tables And Figures

After both CUQDyn and PyMC runs finish, run in MATLAB:

```matlab
cd('<repo>\pymc_matlab')
compare_cuqdyn_pymc
```

This creates:

```text
pymc_matlab\results\comparison\<timestamp>\
```

Key outputs include:

- `parameter_summary_comparison.csv/.xlsx`
- `trajectory_band_summary_comparison.csv/.xlsx`
- side-by-side CUQDyn-vs-PyMC figures as `.png`, `.pdf`, `.eps`, and `.fig`

## 7. Generate LaTeX Reports From Existing Results

From PowerShell using the PyMC uv environment:

```powershell
cd <repo>\pymc_matlab
uv run python ..\scripts\generate_results_latex_report.py
uv run python ..\scripts\generate_cuqdyn_pymc_comparison_report.py
uv run python ..\scripts\generate_combined_tutorial_latex.py
```

These scripts do not rerun inference. They read the latest result folders and write date-stamped reports under `REPORTS/`:

```text
REPORTS\CUQDyn1plus_results_report_<today>\
REPORTS\CUQDyn_vs_PyMC_comparison_<today>\
REPORTS\CUQDyn1plus_combined_tutorial_<today>\
```

## 8. Manuscript Update Checklist

Copy the regenerated `.pdf` figures needed by the manuscript into the manuscript `figures/` folder. The most commonly used sources are:

```text
<repo>\REPORTS\CUQDyn1plus_results_report_<today>\figures\
<repo>\REPORTS\CUQDyn_vs_PyMC_comparison_<today>\figures\
<repo>\REPORTS\CUQDyn1plus_combined_tutorial_<today>\figures\
```

If the manuscript uses appendix tables, also copy or include the generated `.tex`, `.csv`, and `.xlsx` tables from the same `REPORTS/` folders.

## 9. Expected Date Convention

The report-generation scripts create folders ending in the current date, for example on 2026-07-13:

```text
CUQDyn1plus_results_report_2026-07-13
CUQDyn_vs_PyMC_comparison_2026-07-13
CUQDyn1plus_combined_tutorial_2026-07-13
```

The MATLAB example folders use timestamped names with date and time. Use the latest timestamped folder for each example unless you intentionally pinned a specific run.
