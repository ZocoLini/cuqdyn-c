#!/usr/bin/env python3
"""Layer-6 comparison: MATLAB seed ensemble vs C seed ensemble.

Layers 2 and 4 are compared by the C harness (test_baseline) and layer 3 by
test_cost_replay; this script handles the only layer where a scalar pass/fail
makes no sense, because both sides ran a stochastic optimiser. Instead it
compares the two *distributions*:

  - per-parameter theta_hat: median and IQR side by side, plus the ratio of
    medians and whether the IQRs overlap;
  - band width per state (mean over time of q_up - q_low): ratio of medians;
  - empirical coverage of the true trajectory by the bands, per state.

Usage (run_validation.sh layer 6 calls it like this):
    python3 compare_baseline.py lv2 --matlab-dir OUT/matlab --c-dir OUT/c         --report OUT/report.md

Writes the report and, when matplotlib is available, a PNG per figure next to
it. Exit code 0 always: layer 6 is a report to be
read, not a gate - the numbers need a human eye precisely because optimiser
noise is part of what is being measured.
"""

import argparse
import os
import re
import sys

import numpy as np

# ----------------------------------------------------------------- parsing --


def read_matrix(path):
    """Plain 'rows cols' + values format used across the project."""
    with open(path) as f:
        rows, cols = (int(x) for x in f.readline().split())
        data = np.loadtxt(f)
    return data.reshape(rows, cols)


def parse_c_results(path):
    """Parse the [Section] blocks of cuqdyn-results.txt into arrays."""
    sections = {}
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    i = 0
    while i < len(lines):
        m = re.match(r"\[(\w+)\]", lines[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        header = lines[i + 1].split()
        if len(header) == 1:  # vector: length, then one line of values
            n = int(header[0])
            values = np.array([float(x) for x in lines[i + 2].split()])
            assert len(values) == n, f"{name}: expected {n} values"
            sections[name] = values
            i += 3
        else:  # matrix: rows cols, then rows lines
            rows, cols = int(header[0]), int(header[1])
            block = [[float(x) for x in lines[i + 2 + r].split()] for r in range(rows)]
            sections[name] = np.array(block)
            i += 2 + rows
    return sections


def read_seconds(d):
    """Wall clock of one seed, or None when the run predates the timing file."""
    path = os.path.join(d, "timing.txt")
    if not os.path.isfile(path):
        return None
    with open(path) as f:
        for line in f:
            if line.startswith("seconds"):
                return float(line.split()[1])
    return None


def load_matlab_seeds(root):
    seeds = []
    if not os.path.isdir(root):
        sys.exit(f"No {root} - run gen_baseline('<model>', 5, seeds) first")
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if not name.startswith("seed_") or not os.path.isfile(
            os.path.join(d, "q_up.txt")
        ):
            continue
        seeds.append(
            {
                "theta_hat": read_matrix(os.path.join(d, "theta_hat.txt")).ravel(),
                "params_median": read_matrix(
                    os.path.join(d, "params_median.txt")
                ).ravel(),
                "q_low": read_matrix(os.path.join(d, "q_low.txt")),
                "q_up": read_matrix(os.path.join(d, "q_up.txt")),
                "seconds": read_seconds(d),
            }
        )
    if not seeds:
        sys.exit(f"{root} has no finished seed_* directories")
    return seeds


def load_c_seeds(root):
    seeds = []
    if not os.path.isdir(root):
        sys.exit(f"No C runs under {root} - run: run_validation.sh layer 6 --side=c")
    for name in sorted(os.listdir(root)):
        path = os.path.join(root, name, "cuqdyn-results.txt")
        if not name.startswith("seed_") or not os.path.isfile(path):
            continue
        sec = parse_c_results(path)
        seeds.append(
            {
                "theta_hat": sec["ParamsInit"],
                "params_median": sec["Params"],
                "q_low": sec["Q_low"],
                "q_up": sec["Q_up"],
                "seconds": read_seconds(os.path.join(root, name)),
            }
        )
    if not seeds:
        sys.exit(f"{root} has no finished seed_*/cuqdyn-results.txt")
    return seeds


# ---------------------------------------------------------------- analysis --


def iqr(x, axis=0):
    lo, hi = np.percentile(x, [25, 75], axis=axis)
    return lo, hi


def param_table(mat_seeds, c_seeds, key, title):
    m = np.array([s[key] for s in mat_seeds])
    c = np.array([s[key] for s in c_seeds])
    if m.shape[1] != c.shape[1]:
        sys.exit(f"{title}: MATLAB has {m.shape[1]} params, C has {c.shape[1]}")

    med_m, med_c = np.median(m, axis=0), np.median(c, axis=0)
    lo_m, hi_m = iqr(m)
    lo_c, hi_c = iqr(c)
    # A strongly identified problem collapses both IQRs to near-zero width at
    # slightly offset points; strict interval intersection then reports "NO"
    # for medians that agree to 4 digits. Count as agreement either real
    # overlap or medians within 0.1% of each other.
    med_close = np.abs(med_c - med_m) <= 1e-3 * np.maximum(np.abs(med_m), 1e-300)
    overlap = ((lo_m <= hi_c) & (lo_c <= hi_m)) | med_close
    with np.errstate(divide="ignore", invalid="ignore"):
        ratio = np.where(med_m != 0, med_c / med_m, np.nan)

    lines = [
        f"### {title}",
        "",
        "| param | MATLAB median [IQR] | C median [IQR] | C/MATLAB | IQRs overlap |",
        "|---|---|---|---|---|",
    ]
    for j in range(m.shape[1]):
        lines.append(
            f"| p{j + 1} | {med_m[j]:.4g} [{lo_m[j]:.4g}, {hi_m[j]:.4g}] "
            f"| {med_c[j]:.4g} [{lo_c[j]:.4g}, {hi_c[j]:.4g}] "
            f"| {ratio[j]:.3f} | {'yes' if overlap[j] else '**NO**'} |"
        )
    lines.append("")
    n_no = int((~overlap).sum())
    lines.append(
        f"Parameters in disagreement (no IQR overlap and medians >0.1% apart): "
        f"**{n_no} / {m.shape[1]}**. "
        "With >=10 seeds per side, more than one deserves a look."
    )
    lines.append("")
    return lines, overlap


def band_tables(mat_seeds, c_seeds, truth, times):
    widths_m = np.array([s["q_up"] - s["q_low"] for s in mat_seeds])  # seeds x m x ns
    widths_c = np.array([s["q_up"] - s["q_low"] for s in c_seeds])
    mean_w_m = widths_m[:, 1:, :].mean(axis=1)  # per-seed mean width, skip t0
    mean_w_c = widths_c[:, 1:, :].mean(axis=1)
    med_w_m = np.median(mean_w_m, axis=0)
    med_w_c = np.median(mean_w_c, axis=0)

    cov_m = coverage(mat_seeds, truth)
    cov_c = coverage(c_seeds, truth)

    ns = truth.shape[1]
    lines = [
        "### Bands per state",
        "",
        "| state | MATLAB median width | C median width | C/MATLAB | MATLAB coverage | C coverage |",
        "|---|---|---|---|---|---|",
    ]
    for k in range(ns):
        with np.errstate(divide="ignore", invalid="ignore"):
            r = med_w_c[k] / med_w_m[k] if med_w_m[k] != 0 else np.nan
        lines.append(
            f"| y{k + 1} | {med_w_m[k]:.4g} | {med_w_c[k]:.4g} | {r:.3f} "
            f"| {cov_m[k]:.3f} | {cov_c[k]:.3f} |"
        )
    lines.append("")
    lines.append(
        "Coverage = fraction of points (t>0, all seeds) where the true "
        "trajectory falls inside [q_low, q_up]. Nominal is "
        "1 - 2*alp (0.95 for lv2, 0.90 for nfkb)."
    )
    lines.append("")
    return lines


def timing_table(mat_seeds, c_seeds):
    """Median wall clock per seed on each side, and how many times faster C is.

    Medians rather than means: one seed landing in a hard basin should not set
    the number. Runs made before timing.txt existed simply have no entry.
    """
    m = [s["seconds"] for s in mat_seeds if s["seconds"] is not None]
    c = [s["seconds"] for s in c_seeds if s["seconds"] is not None]
    if not m or not c:
        missing = "MATLAB" if not m else "C"
        return [
            "### Wall clock",
            "",
            f"No data on the {missing} side: those runs predate "
            "timing.txt. Re-running the campaign fills it in.",
            "",
        ]

    med_m, med_c = float(np.median(m)), float(np.median(c))
    lines = [
        "### Wall clock",
        "",
        "| side | seeds timed | median s/seed | min | max |",
        "|---|---|---|---|---|",
        f"| MATLAB | {len(m)} | {med_m:.1f} | {min(m):.1f} | {max(m):.1f} |",
        f"| C | {len(c)} | {med_c:.1f} | {min(c):.1f} | {max(c):.1f} |",
        "",
    ]
    if med_c > 0:
        lines.append(
            f"**C is {med_m / med_c:.1f}x faster** per seed, comparing medians "
            "at the same evaluation budget. This compares whole "
            "pipelines, not kernels: integration, the LOO loop and "
            "the band computation are all included."
        )
        lines.append("")
    return lines


def coverage(seeds, truth):
    ns = truth.shape[1]
    inside = np.zeros(ns)
    total = 0
    for s in seeds:
        ok = (truth[1:, :] >= s["q_low"][1:, :]) & (truth[1:, :] <= s["q_up"][1:, :])
        inside += ok.sum(axis=0)
        total += ok.shape[0]
    return inside / total


def maybe_plots(mat_seeds, c_seeds, outstem):
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        return ["(matplotlib not available: no figures)", ""]

    m = np.array([s["theta_hat"] for s in mat_seeds])
    c = np.array([s["theta_hat"] for s in c_seeds])
    n = m.shape[1]

    fig, ax = plt.subplots(figsize=(max(6, 0.6 * n), 4))
    positions_m = np.arange(n) - 0.18
    positions_c = np.arange(n) + 0.18
    bm = ax.boxplot(m, positions=positions_m, widths=0.3, patch_artist=True)
    bc = ax.boxplot(c, positions=positions_c, widths=0.3, patch_artist=True)
    for box in bm["boxes"]:
        box.set_facecolor("#4878CF")
    for box in bc["boxes"]:
        box.set_facecolor("#EE854A")
    ax.set_xticks(range(n))
    ax.set_xticklabels([f"p{j + 1}" for j in range(n)], rotation=45)
    ax.set_yscale("log")
    ax.set_title("theta_hat per seed: MATLAB (blue) vs C (orange)")
    fig.tight_layout()
    png = f"{outstem}_theta.png"
    fig.savefig(png, dpi=120)
    plt.close(fig)
    return [f"![theta_hat]({os.path.basename(png)})", ""]


# -------------------------------------------------------------------- main --


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("model", help="problem name")
    ap.add_argument("--matlab-dir", required=True, help="MATLAB seeds (seed_<k>/)")
    ap.add_argument("--c-dir", required=True, help="C seeds (seed_<k>/)")
    ap.add_argument("--report", required=True, help="markdown report to write")
    args = ap.parse_args()

    mat_root = args.matlab_dir
    c_root = args.c_dir

    mat_seeds = load_matlab_seeds(mat_root)
    c_seeds = load_c_seeds(c_root)
    # The true trajectory and the time grid describe the problem: the MATLAB
    # side writes them next to its seeds, so the report needs nothing else.
    truth = read_matrix(os.path.join(mat_root, "truth.txt"))
    times = read_matrix(os.path.join(mat_root, "times.txt")).ravel()

    rel = os.path.abspath

    lines = [
        f"# Layer-6 baseline - {args.model}",
        "",
        f"MATLAB: {len(mat_seeds)} seeds ({rel(mat_root)})",
        f"C:      {len(c_seeds)} seeds ({rel(c_root)})",
        "",
        "Both sides run the full pipeline with their own stochastic "
        "optimiser; what is comparable are the distributions, not the "
        "seeds one by one.",
        "",
    ]

    t1, _ = param_table(
        mat_seeds, c_seeds, "theta_hat", "theta_hat (fit on the full data)"
    )
    t2, _ = param_table(
        mat_seeds, c_seeds, "params_median", "Median parameters of the LOO ensemble"
    )
    lines += t1 + t2
    lines += band_tables(mat_seeds, c_seeds, truth, times)
    lines += timing_table(mat_seeds, c_seeds)
    report = args.report
    lines += maybe_plots(mat_seeds, c_seeds, os.path.splitext(report)[0])

    with open(report, "w") as f:
        f.write("\n".join(lines))
    print(f"Report written: {report}")
    print("\n".join(lines[:40]))


if __name__ == "__main__":
    main()
