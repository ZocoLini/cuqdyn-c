# Validating the C port against the MATLAB reference

The C/Rust code is a transpilation of the MATLAB in `CUQDyn1_Plus/` and
`CUQDyn/`. This directory checks that the transpilation is faithful.

## The problem with comparing end to end

The obvious validation — run the CLI, run `CUQDyn1_Plus.m`, diff the bands —
does not work, because eSS is a stochastic global optimiser. Two runs of the
*same* implementation with different seeds already produce different `θ̂`,
different LOO ensembles, and therefore different bands. A diff between C and
MATLAB would be dominated by optimiser noise, and a real transpilation bug
worth a few percent would be invisible underneath it.

So the validation is layered, cheapest and sharpest first.

| Layer | What it compares | Optimiser noise | Status |
|---|---|---|---|
| 1 | Deterministic kernels on identical inputs | none | **implemented here** |
| 2 | Trajectory sensitivities: CVODES vs complex-step | none | not yet |
| 3 | ODE integration at fixed parameters | none | done ad hoc in 2025 |
| 4 | Full pipeline with `θ̂` and the LOO ensemble injected | none | not yet |
| 5 | Full pipeline, many seeds, distributions compared | dominant | not yet |

Layer 1 is where transpilation bugs actually live: `fim.c` alone is 471 lines
of GSL linear algebra standing in for about 60 lines of MATLAB.

## Layer 1: golden vectors

`gen_golden.m` calls the MATLAB kernels on fixed synthetic inputs and writes
both the inputs and the outputs to `golden/`. `test_golden.c` feeds the same
inputs to the C kernels and compares.

Crucially, none of these kernels touch MEIGO or the ODE solver — they are pure
linear algebra — so the golden vectors can be generated without a working
MEIGO install, and the comparison is exact up to floating-point library
differences (LAPACK vs GSL).

### Covered

- `cuqdyn_fim_covariance` — 9 cases: log and natural parameterization, both
  covariance methods, `sigma2 ≠ 1`, an exactly rank-deficient Jacobian, the
  non-positive-parameter fallback, an ill-conditioned system in the spirit of
  NF-kB, and a larger random problem. Compares `Cov_p`, `Cov_log`, the
  singular values, rank, ridge, condition number and rank tolerance.
- The hybrid covariance `D_FIM · R_LOO · D_FIM` — 4 cases, including a frozen
  parameter (zero-variance column) and the two-refit minimum.
- `cuqdyn_residual_variance` — 4 cases, including the degrees-of-freedom clamp.
- `quantile` — 6 vectors × 9 probabilities. The C reimplements MATLAB's
  interpolated quantile in `matlab.c`, and the conformal bands depend on it
  directly, so its edge cases (even/odd length, probabilities outside
  `[0.5/n, (n-0.5)/n]`, single element) matter.

### Deliberately not covered, and why

- **The weak-direction reliability diagnostic.** MATLAB's
  `cuqdyn_fim_covariance` also returns `max_weak_fraction` and
  `any_unreliable_bands` from `local_reliability()`. The C port never computes
  them: `weak_fraction_threshold` is parsed from the XML and threaded all the
  way to `FimOptions` but never read, and `FimResult.v` is filled and freed
  without being used. There is nothing to compare. `test_golden.c` prints a
  `NOT IMPLEMENTED IN C` line wherever a golden case carries the expected
  value, so the gap does not quietly disappear.
- **The parametric bootstrap** (paper §2.7). Not ported at all; tracked in
  `TODO` as "Bootstrap trayectorial".
- **The PSD clamp branch** of the hybrid covariance. None of the four
  generated ensembles produced a negative eigenvalue, so that branch is still
  unexercised. Constructing an ensemble that reliably triggers it is worth
  doing.

## Running it

Generate the golden vectors (needs MATLAB; the reference was produced with
R2024a):

```bash
cd validation
matlab -batch "gen_golden"
```

`golden/` is committed, so this only needs re-running when the MATLAB
reference changes.

Then build and run the comparison. On CESGA the default `cargo` in `PATH` is
1.45.1 from 2020 and cannot build the crate, and `scripts/build.sh` does not
load a Rust module, so load one explicitly:

```bash
module load cesga/2025 gcc/13.4.0 openmpi/5.0.7 rust/1.88.0
mkdir -p build-serial && cd build-serial
cmake -DCMAKE_TOOLCHAIN_FILE=../toolchains/serial_toolchain.cmake ..
make -j 8
ctest -R validation_golden --output-on-failure
```

Or run the binary directly for the full per-check table:

```bash
./build-serial/validation/test_golden validation/golden 1e-9
```

The exit code is the number of failing comparisons.

## Result as of 2026-08-18

**79 checks, 0 failed**, against MATLAB R2024a, built with `gcc/13.4.0` on
ft3.cesga.es. Every well-conditioned case agrees to `1e-14` relative or better
— i.e. to floating-point noise. The deterministic UQ mathematics is a faithful
transpilation.

## Interpreting the tolerance

The default is `1e-9` relative, scaled by the largest magnitude in the
expected array rather than element-wise — element-wise ratios explode on
entries that are legitimately near zero.

One case carries its own tolerance, and the reason matters:

`fim_04_rank_deficient` builds a `J` whose third column is exactly the sum of
the other two, so `J'J` is singular and the only thing making it invertible is
the ridge, `1e-12 * smax^2 = 2.02e-10`. That leaves
`cond(J'J + ridge*I) = 1.0e12`, and inverting a matrix that ill-conditioned
amplifies rounding by `eps * cond = 2.2e-4`. LAPACK and GSL cannot agree to
better than that however faithful the port is. The observed difference is
`9.5e-6`, comfortably inside the bound, so the case is given a `1e-3`
tolerance derived from the conditioning rather than fitted to the observed
number. **A difference beyond `1e-3` there would be a genuine defect.**

The wider lesson is about the method, not the port: when the FIM is rank
deficient and `relative_ridge` is used, the covariance is numerically
meaningless well above the `1e-5` level in *either* implementation. That is
the concrete form of the paper's warning that "for weakly identifiable
systems, the numerical covariance is necessarily regularization-dependent",
and it is an argument for reading the rank and condition number that
`delta_bands.c` already prints.

Note that `fim_07_ill_conditioned` (`cond(J) ~ 1.7e7`) needs no such
allowance — it agrees to `1e-19`. Ill-conditioning in `J` alone is survivable;
exact rank deficiency plus a tiny ridge is not.

## Build gotcha on CESGA

Incremental builds on the Lustre scratch filesystem have produced a
`libcuqdyn-c.a` whose archive index was missing entries for members that were
present in the archive (`matlab.c.o`, `ode_solver.c.o`), so the link failed
with `undefined reference to quantile` / `solve_ode` while `nm` showed the
symbols defined. If that happens, force a fresh archive:

```bash
rm -f build-serial/modules/cuqdyn-c/libcuqdyn-c.a
make cuqdyn-c
```

Check with `nm -s libcuqdyn-c.a | sed -n '/Archive index/,/^$/p' | wc -l` —
a healthy archive currently has 49 index entries, the broken one had 36.

## What a green run does and does not prove

It proves the deterministic UQ mathematics was transpiled correctly. It says
nothing about the ODE integration, the sensitivities, the eSS interface, or
the MPI sharding — those are layers 2 to 5 and are still open.
