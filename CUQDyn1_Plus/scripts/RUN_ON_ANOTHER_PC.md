# Running the full CUQDyn1_Plus evaluation on another (faster) PC

This is a from-scratch setup + launch guide for reproducing the entire
manuscript pipeline (`scripts/run_full_evaluation.m`) on a different machine.
It targets **Windows 11 + MATLAB** (the reference environment) and notes the few
Linux differences inline. Follow sections 1–5 once, then launch in section 6.

The pipeline runs seven stages: `validate → examples → tutorial → sbc → pymc →
compare → reports`. **`sbc` is the multi-hour bottleneck** and is what makes a
fast, many-core machine worthwhile.

---

## 1. Hardware recommendations

| Resource | Minimum | Recommended (fast) | Why |
|---|---|---|---|
| CPU cores | 8 physical | 16–32+ physical | `sbc` (SBC LOO loop) parallelises over replicates via `parpool` |
| RAM | 16 GB | 32–64 GB | NF-κB fits + multiple parallel workers |
| Disk | 5 GB free | 10 GB free | Result folders, figures, PyTensor compile cache |
| GPU | not used | — | Nothing here uses a GPU |

On the 14-core reference machine: `examples` ≈ 68 min, `tutorial` ≈ 24 min,
`sbc` ≈ many hours (the whole run is ~a day). More physical cores + the
**Parallel Computing Toolbox** is the single biggest speed-up for `sbc`.

---

## 2. Software prerequisites

### 2.1 MATLAB + toolboxes
- **MATLAB R2020a or later** (reference: R2026a). `exportgraphics` (R2020a+) is
  required for figure saving.
- Required toolboxes:
  - **Statistics and Machine Learning Toolbox** (`norminv`, `quantile`)
  - **Optimization Toolbox** (`lsqnonlin`, the local refinement inside MEIGO)
- **Parallel Computing Toolbox** — *optional but strongly recommended*; the SBC
  LOO loop uses `parpool`. Without it SBC still runs but far slower.
- Note the full path to `matlab.exe`, e.g. `C:\Program Files\MATLAB\R2026a\bin\matlab.exe`.

### 2.2 Git
Install Git for Windows (provides `git` and a bash shell). Configure identity:
```powershell
git config --global user.name  "Your Name"
git config --global user.email "you@csic.es"
```

### 2.3 C++ toolchain + BLAS (only needed for the `pymc`/`reports` stages)
PyMC/PyTensor compiles C++ at runtime, so it needs a compiler and BLAS. The
reference setup uses **MSYS2 / UCRT64**:
1. Install MSYS2 from <https://www.msys2.org> (default `C:\msys64`).
2. In the **MSYS2 UCRT64** shell, install the toolchain + OpenBLAS:
   ```bash
   pacman -Syu
   pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-openblas
   ```
   This provides `g++` and `openblas` under `C:\msys64\ucrt64\bin` and
   `C:\msys64\ucrt64\lib`.
3. Add `C:\msys64\ucrt64\bin` to your **persistent user PATH** (Settings →
   Environment Variables), then open a fresh shell. Verify: `g++ --version`.

*(Linux: install `g++`/`gcc` and `libopenblas-dev` via your package manager;
skip the MSYS2 steps. Set BLAS in `~/.pytensorrc` as in 4.2 if needed.)*

### 2.4 uv (Python environment manager)
Install `uv` (fast Python/venv manager): <https://docs.astral.sh/uv/>. On Windows:
```powershell
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```
`uv` will fetch the pinned Python itself (the project needs **Python ≥ 3.14**).

---

## 3. Get the code

### 3.1 Clone the repository
```powershell
cd C:\work    # wherever you want it; avoid spaces in the path if possible
git clone https://git.csic.es/codex_t14/CUQDyn1_Plus_v2026.git
cd CUQDyn1_Plus_v2026
git checkout codex/CUQDyn1_Plus_v22May26
```
Call this folder `<repo>` below.

### 3.2 MEIGO64 optimiser (required)
The runner does **not** auto-download MEIGO. The simplest, zero-config option is
to clone it **into the repo** as `MEIGO64-master` — the runner auto-detects that
location, so you never touch `MEIGO64_PATH`:
```powershell
git clone --depth 1 https://github.com/gingproc-IIM-CSIC/MEIGO64.git <repo>\MEIGO64-master
```
(`MEIGO64-master/` is git-ignored, so it won't dirty the working tree. The
prebuilt `nl2sol.mexw64` ships with it; the default local solver is `lsqnonlin`.)

---

## 4. Configure the PyMC / PyTensor toolchain

Only needed for the `pymc` and `reports` stages. If you only want the MATLAB
stages (`validate,examples,tutorial,sbc`), skip section 4.

### 4.1 PATH
Ensure `C:\msys64\ucrt64\bin` is on PATH (2.3). MATLAB shells out to `uv`, and
PyTensor auto-detects `g++` from PATH.

### 4.2 BLAS config (`~/.pytensorrc`)
Create `%USERPROFILE%\.pytensorrc` so PyTensor links OpenBLAS cleanly:
```ini
[blas]
ldflags = -LC:/msys64/ucrt64/lib -LC:/msys64/ucrt64/bin -lopenblas
```
If PyTensor compilation ever fails on a locked-down machine, point the compile
cache somewhere writable before launching:
```powershell
$env:PYTENSOR_FLAGS = "base_compiledir=$env:TEMP\pytensor_cache"
```

### 4.3 Build the Python env
```powershell
cd <repo>\pymc_matlab
uv sync                 # creates .venv with pymc>=5.28, numpy, scipy, ...
uv run python -m py_compile lv_pymc.py sir_pymc.py ap_pymc.py nfkb_pymc.py pymc_export_utils.py
```

---

## 5. One-time verification (fast, no optimiser runs)

From MATLAB, with the repo + MEIGO on the path:
```matlab
cd('<repo>')
addpath(genpath(pwd))
addpath(genpath(fullfile(pwd,'MEIGO64-master')))
summary = validate_cuqdyn_repo();     % expect all checks PASS
run_full_evaluation('list')           % prints the 7 stage names
```
If `validate_cuqdyn_repo` passes and `list` prints 7 stages, you're ready.

---

## 6. Launch the full run

The runner is designed for unattended `matlab -batch`. Because it auto-detects
`<repo>\MEIGO64-master` (from 3.2), no `MEIGO64_PATH`/`MeigoPath` is needed.

### 6a. Windows — detached (recommended for the long run)
Run this in PowerShell (adjust the two paths):
```powershell
$repo = 'C:\work\CUQDyn1_Plus_v2026'
$mat  = 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe'
Start-Process -FilePath $mat `
  -ArgumentList '-batch', "addpath(genpath('$repo')); run_full_evaluation" `
  -WorkingDirectory "$repo\scripts"
```
> **Quoting tip:** if you pass extra arguments that contain spaces or brackets
> (e.g. `'Stages', {'sbc','pymc'}`), `Start-Process` will split them and MATLAB
> receives a broken command. In that case put the call in a one-line wrapper
> `.m` file and launch it by its **space-free name**:
> ```powershell
> # wrapper.m contains: addpath(genpath('<repo>')); run_full_evaluation('Stages', {'sbc','pymc','compare','reports'})
> Start-Process -FilePath $mat -ArgumentList '-batch','wrapper' -WorkingDirectory '<folder-of-wrapper>'
> ```

### 6b. Windows — foreground (blocks the shell until done)
```powershell
cd <repo>\scripts
matlab -batch "addpath(genpath('C:\work\CUQDyn1_Plus_v2026')); run_full_evaluation"
```

### 6c. Linux
```bash
cd <repo>/scripts
matlab -batch "addpath(genpath('<repo>')); run_full_evaluation"
```

### Useful options
- `run_full_evaluation('Stages', {'examples','tutorial'})` — run a subset.
- `run_full_evaluation('MeigoPath','<path>\MEIGO64-master')` — if MEIGO lives
  elsewhere (not in `<repo>`).
- `run_full_evaluation('UseFastSBC', true)` — quick SBC dev check; note `reports`
  is then skipped unless you also pass `'AllowFastReports', true`.
- `run_full_evaluation('RunUvSync', false)` — skip `uv sync` if already synced.

---

## 7. Monitor the run

Live diary + machine-aware summary are written under
`<repo>\scripts\eval_logs\<timestamp>\`:
```powershell
# newest diary, follow the tail
$log = Get-ChildItem <repo>\scripts\eval_logs -Recurse -Filter run_full_evaluation.log |
       Sort-Object LastWriteTime | Select-Object -Last 1
Get-Content $log.FullName -Wait -Tail 40
```
When the run ends it prints a final `Done:` line and writes
`evaluation_summary.csv` (per-stage status + elapsed seconds) in the same folder.

---

## 8. Outputs

- `EXAMPLES/<model>/Results_*_<timestamp>/` — per-example CUQDyn results.
- `EXAMPLES/Master_Run_Results_<timestamp>/` — example-suite master + machine info.
- `EXAMPLES/LV/Tutorial_LV_three_UQ_methods_<timestamp>/` — three-method tutorial.
- `EXAMPLES/<model>/SBC_Results_*_<timestamp>/` — SBC calibration.
- `pymc_matlab/results/{lv,sir,ap,nfkb}/` and `.../results/comparison/<timestamp>/`.
- `REPORTS/CUQDyn1plus_results_report_<date>/`, `.../CUQDyn_vs_PyMC_comparison_<date>/`,
  `.../CUQDyn1plus_combined_tutorial_<date>/` — LaTeX/CSV/XLSX + figures.

The report generators pick the **latest** folder per model, so a clean machine
that runs everything once produces a self-consistent same-day set.

---

## 9. Troubleshooting (issues actually hit on the reference machine)

- **`MEIGO NOT FOUND` / optimisation stages fail** — MEIGO isn't on the path.
  Easiest fix: clone it to `<repo>\MEIGO64-master` (3.2). Otherwise set
  `$env:MEIGO64_PATH` in the *same* shell that launches MATLAB, or pass
  `'MeigoPath', ...`. A `matlab -batch` child inherits env vars from the shell
  that starts it; the trap is a value set in a different shell or never set.
- **MATLAB exits instantly, empty logs** — the `-batch` argument was split by
  `Start-Process` (spaces/brackets in the command). Use the space-free wrapper
  trick in 6a.
- **PyTensor: "g++ not available" / slow Python fallback** — `C:\msys64\ucrt64\bin`
  not on PATH for the launching shell. Add it and relaunch.
- **BLAS warnings from PyTensor** — add the `~/.pytensorrc` `[blas]` block (4.2).
- **PyTensor compile errors on a locked-down disk** — set
  `PYTENSOR_FLAGS=base_compiledir=<writable dir>` (4.2).
- **Figures look dark** — set MATLAB to the **Light** theme before running so
  manuscript figures render on white (the runner logs the active theme).

---

## 10. Faster / partial options

- **Split the run across sessions.** Run heavy stages separately and resume
  later; the dependency gate only enforces *in-run* prerequisites, so
  consumers reuse existing outputs:
  ```matlab
  run_full_evaluation('Stages', {'validate','examples','tutorial'})   % day 1
  run_full_evaluation('Stages', {'sbc','pymc','compare','reports'})   % day 2
  ```
- **Quick pipeline smoke test** (not manuscript-grade): `UseFastSBC=true`
  shrinks SBC dramatically. Keep `reports` off unless you also set
  `AllowFastReports=true`, since `*_fast` SBC folders don't match the standard
  report prefixes.
- **MATLAB stages only** (no Python toolchain): run
  `{'validate','examples','tutorial','sbc'}` and skip section 4 entirely.
