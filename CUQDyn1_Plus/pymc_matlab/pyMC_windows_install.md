# PyMC Windows Install Notes

These notes describe the minimal Windows 11 setup used for the PyMC comparison
scripts in this folder. The upstream PyMC site is:

https://www.pymc.io/welcome.html

PyMC's official installation page recommends conda/Miniforge for general use.
This project is configured for `uv`, so the local workflow below uses the
checked-in `pyproject.toml` and `uv.lock`.

## 1. Install `uv`

Install `uv` in PowerShell:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Close and reopen PowerShell, then check:

```powershell
uv --version
```

`uv` manages Python versions and the project virtual environment, so no
separate global Python installation is required for this workflow.

## 2. Install VS Code Python Support

Install Visual Studio Code from:

```text
https://code.visualstudio.com/
```

Then install the Microsoft Python extension. From PowerShell this can be
checked with:

```powershell
code --list-extensions | Select-String ms-python.python
```

When opening this folder in VS Code, select the project interpreter:

1. Press `Ctrl+Shift+P`.
2. Choose `Python: Select Interpreter`.
3. Select the interpreter under `pymc_matlab\.venv`.

## 3. Install The Windows C/C++ Toolchain

PyMC uses PyTensor, which may compile numerical code locally. On Windows, a
working C/C++ compiler avoids many PyTensor failures.

Install MSYS2 from:

```text
https://www.msys2.org/
```

The fastest command-line install path is:

```powershell
winget install --id MSYS2.MSYS2 -e
```

The graphical installer from the MSYS2 website is also fine. Use the default
installation location, `C:\msys64`, unless you have a specific reason to choose
another folder.

Open the **MSYS2 UCRT64** terminal and install GCC:

```bash
pacman -S mingw-w64-ucrt-x86_64-gcc
```

Add the UCRT64 compiler folder to the Windows `Path`:

```text
C:\msys64\ucrt64\bin
```

You can do this through the Windows GUI:

1. Search Windows for `Edit the system environment variables`.
2. Open **Environment Variables**.
3. Edit the user or system `Path`.
4. Add `C:\msys64\ucrt64\bin`.

For a non-admin PowerShell session, a user-level `Path` update is usually the
safest command-line option:

```powershell
$oldPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($oldPath -notlike '*C:\msys64\ucrt64\bin*') {
    [Environment]::SetEnvironmentVariable('Path', "C:\msys64\ucrt64\bin;$oldPath", 'User')
}
```

Avoid using an admin-level machine `Path` update from a non-elevated shell; it
can fail with "Requested registry access is not allowed".

After editing `Path`, close and reopen every application that needs to see the
new compiler path: PowerShell, VS Code terminals, MATLAB, and any other open
terminal windows. Then verify:

```powershell
gcc --version
g++ --version
```

You can also check that the expected MSYS2 package is installed:

```powershell
C:\msys64\usr\bin\bash.exe -lc "pacman -Q mingw-w64-ucrt-x86_64-gcc"
```

## 4. Create The Python Environment

From the repository root:

```powershell
cd <repo>\pymc_matlab
uv sync
```

This creates `.venv/` and installs the dependencies declared in
`pyproject.toml`, including PyMC, NumPy, SciPy, pandas, matplotlib, and ArviZ.

Quick Python check:

```powershell
uv run python -c "import pymc, numpy, scipy, pandas, matplotlib, arviz; print('PyMC environment OK')"
```

Optional script syntax check:

```powershell
uv run python -m py_compile lv_pymc.py sir_pymc.py ap_pymc.py nfkb_pymc.py pymc_export_utils.py
```

Full environment check:

```powershell
uv run python -c "import sys, shutil, pymc, arviz, numpy, pandas, matplotlib, pytensor; print('python', sys.version.split()[0]); print('pymc', pymc.__version__); print('pytensor', pytensor.__version__); print('gcc', shutil.which('gcc')); print('g++', shutil.which('g++'))"
```

The `gcc` and `g++` lines should point to `C:\msys64\ucrt64\bin`.

## 5. Check The Required Data Files

The PyMC scripts read the same CSV files as the MATLAB CUQDyn examples. From
the `pymc_matlab/` folder, check that the following files exist:

```text
..\EXAMPLES\LV\data\lv2_synthetic_data_noi10_partobs_1.csv
..\EXAMPLES\SIR\data\sir_data.csv
..\EXAMPLES\AP\data\AP_measurementData_1_4.csv
..\EXAMPLES\NFKB\data\NFKB_synthetic_data_5n_36st_partobs10.csv
```

If one is missing, regenerate it with the corresponding script in
`EXAMPLES\<model>\data_generation\`.

## 6. Run PyMC Directly

Run from `pymc_matlab/`:

```powershell
uv run python lv_pymc.py
uv run python sir_pymc.py
uv run python ap_pymc.py
uv run python nfkb_pymc.py
```

The scripts write outputs under `pymc_matlab\results\<model>\`.

NF-kB is much slower than the other examples. Expect it to take substantially
longer than LV, SIR, or AP. Approximate runtimes from one 24-core Xeon Windows
workstation were:

| Model | Default draw setting | Approximate runtime |
|---|---:|---:|
| LV | 4000 draws x 4 chains | 8 min |
| SIR | 1000 draws x 4 chains | 3 min |
| AP | 1000 draws x 4 chains | 3 min |
| NF-kB | 1000 draws x 4 chains | 28 min |
| NF-kB sensitivity | 4000 draws x 4 chains | 90 min |

Treat these as planning numbers only; runtimes depend strongly on CPU, BLAS,
disk/cache behavior, and PyTensor compilation state.

## 7. Run From MATLAB

MATLAB must be able to find `uv` from its system shell. In MATLAB:

```matlab
[status, out] = system('uv --version');
disp(out)
assert(status == 0, 'MATLAB cannot find uv on PATH.');
```

If MATLAB cannot find `uv`, restart MATLAB after installing `uv`. If it still
cannot find it, add the `uv` install location to the Windows user `PATH`, then
restart MATLAB again.

Run the wrappers from the `pymc_matlab` folder:

```matlab
cd('<repo>\pymc_matlab')

run_bayes_lv
run_bayes_sir
run_bayes_ap
run_bayes_nfkb
```

Each wrapper calls `uv run python <model>_pymc.py`, then reads the generated CSV
files and saves MATLAB plots into `results\<model>\`.

## 8. Compare With CUQDyn Outputs

After the PyMC runs and the corresponding CUQDyn MATLAB examples have completed:

```matlab
cd('<repo>\pymc_matlab')
compare_cuqdyn_pymc
```

This reads existing result folders and writes comparison tables and figures
under `pymc_matlab\results\comparison\`.

## 9. General `uv` Project Workflow

For a new standalone PyMC project, keep the same isolated-environment pattern:

```powershell
mkdir MyNewProject
cd MyNewProject
uv init
uv add pymc arviz matplotlib pandas
uv run python my_script.py
```

Prefer `uv run python ...` over activating environments manually. It guarantees
that the command uses the dependencies pinned for that project.

## 10. Troubleshooting

- If `uv sync` fails, run it again from `pymc_matlab/`, where `pyproject.toml`
  and `uv.lock` live.
- If `gcc` or `g++` is not found, verify that `C:\msys64\ucrt64\bin` is on the
  Windows `Path`, then close and reopen PowerShell, MATLAB, VS Code, and any
  terminals launched before the `Path` change.
- If PyTensor compilation fails on Windows, set a writable local cache before
  rerunning, for example
  `set PYTENSOR_FLAGS=base_compiledir=%TEMP%\pytensor_cache`, or delete the
  existing `%TEMP%\pytensor_cache\` folder if that cache was already used.
  Note that the maintained `*_pymc.py` scripts set their own Windows PyTensor
  cache at startup:
  `PYTENSOR_FLAGS=compiledir=<repo>\pymc_matlab\.pytensor_cache`. That script
  setting takes priority over a shell-level `PYTENSOR_FLAGS`. To use a custom
  cache, edit the top Windows block in the script or change it to use
  `os.environ.setdefault(...)`.
- If MATLAB says a Python script failed, rerun the same command directly in
  PowerShell, for example `uv run python lv_pymc.py`, to see the full Python
  error output.
- Keep `pymc_matlab\results\` out of Git; it is generated output.
