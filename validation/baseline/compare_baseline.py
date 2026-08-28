#!/usr/bin/env python3
"""Layer-5 comparison: MATLAB seed ensemble vs C seed ensemble.

Layers 3 and 4 are compared by the C harness (test_baseline); this script
handles the only layer where a scalar pass/fail makes no sense, because both
sides ran a stochastic optimiser. Instead it compares the two *distributions*:

  - per-parameter theta_hat: median and IQR side by side, plus the ratio of
    medians and whether the IQRs overlap;
  - band width per state (mean over time of q_up - q_low): ratio of medians;
  - empirical coverage of the true trajectory by the bands, per state.

Usage:
    python3 compare_baseline.py lv2
    python3 compare_baseline.py nfkb --matlab-dir path/ --c-dir path/

Writes report_<model>.md next to this script and, when matplotlib is
available, a PNG per figure. Exit code 0 always: layer 4 is a report to be
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


def load_matlab_seeds(root):
    seeds = []
    layer4 = os.path.join(root, "layer4")
    if not os.path.isdir(layer4):
        sys.exit(f"No layer4/ under {root} - run gen_baseline('<model>', 4, seeds) first")
    for name in sorted(os.listdir(layer4)):
        d = os.path.join(layer4, name)
        if not name.startswith("seed_") or not os.path.isfile(os.path.join(d, "q_up.txt")):
            continue
        seeds.append({
            "theta_hat": read_matrix(os.path.join(d, "theta_hat.txt")).ravel(),
            "params_median": read_matrix(os.path.join(d, "params_median.txt")).ravel(),
            "q_low": read_matrix(os.path.join(d, "q_low.txt")),
            "q_up": read_matrix(os.path.join(d, "q_up.txt")),
        })
    if not seeds:
        sys.exit(f"layer4/ under {root} has no finished seed_* directories")
    return seeds


def load_c_seeds(root):
    seeds = []
    if not os.path.isdir(root):
        sys.exit(f"No C runs under {root} - run run_c_seeds.sh first")
    for name in sorted(os.listdir(root)):
        path = os.path.join(root, name, "cuqdyn-results.txt")
        if not name.startswith("seed_") or not os.path.isfile(path):
            continue
        sec = parse_c_results(path)
        seeds.append({
            "theta_hat": sec["ParamsInit"],
            "params_median": sec["Params"],
            "q_low": sec["Q_low"],
            "q_up": sec["Q_up"],
        })
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

    lines = [f"### {title}", "",
             "| param | MATLAB mediana [IQR] | C mediana [IQR] | C/MATLAB | IQR solapa |",
             "|---|---|---|---|---|"]
    for j in range(m.shape[1]):
        lines.append(
            f"| p{j + 1} | {med_m[j]:.4g} [{lo_m[j]:.4g}, {hi_m[j]:.4g}] "
            f"| {med_c[j]:.4g} [{lo_c[j]:.4g}, {hi_c[j]:.4g}] "
            f"| {ratio[j]:.3f} | {'si' if overlap[j] else '**NO**'} |")
    lines.append("")
    n_no = int((~overlap).sum())
    lines.append(f"Parametros en desacuerdo (sin solape de IQR y medianas a >0.1%): "
                 f"**{n_no} / {m.shape[1]}**. "
                 "Con >=10 semillas por lado, mas de uno merece mirarse.")
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
    lines = ["### Bandas por estado", "",
             "| estado | anchura mediana MATLAB | anchura mediana C | C/MATLAB | cobertura MATLAB | cobertura C |",
             "|---|---|---|---|---|---|"]
    for k in range(ns):
        with np.errstate(divide="ignore", invalid="ignore"):
            r = med_w_c[k] / med_w_m[k] if med_w_m[k] != 0 else np.nan
        lines.append(f"| y{k + 1} | {med_w_m[k]:.4g} | {med_w_c[k]:.4g} | {r:.3f} "
                     f"| {cov_m[k]:.3f} | {cov_c[k]:.3f} |")
    lines.append("")
    lines.append("Cobertura = fraccion de puntos (t>0, todas las semillas) donde la "
                 "trayectoria verdadera cae dentro de [q_low, q_up]. El nominal es "
                 "1 - 2*alp (0.95 para lv2, 0.90 para nfkb).")
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
        return ["(matplotlib no disponible: sin figuras)", ""]

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
    ax.set_title("theta_hat por semilla: MATLAB (azul) vs C (naranja)")
    fig.tight_layout()
    png = f"{outstem}_theta.png"
    fig.savefig(png, dpi=120)
    plt.close(fig)
    return [f"![theta_hat]({os.path.basename(png)})", ""]


# -------------------------------------------------------------------- main --

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", choices=["lv2", "ap", "sir", "nfkb"])
    ap.add_argument("--matlab-dir", default=None, help="default: <here>/matlab/<model>")
    ap.add_argument("--c-dir", default=None, help="default: <here>/c/<model>")
    args = ap.parse_args()

    mat_root = args.matlab_dir or os.path.join(here, "matlab", args.model)
    c_root = args.c_dir or os.path.join(here, "c", args.model)

    mat_seeds = load_matlab_seeds(mat_root)
    c_seeds = load_c_seeds(c_root)
    truth = read_matrix(os.path.join(mat_root, "truth.txt"))
    times = read_matrix(os.path.join(mat_root, "times.txt")).ravel()

    lines = [f"# Baseline capa 5 - {args.model}", "",
             f"MATLAB: {len(mat_seeds)} semillas ({mat_root})",
             f"C:      {len(c_seeds)} semillas ({c_root})", "",
             "Ambos lados corren el pipeline completo con su propio optimizador "
             "estocastico; lo comparable son las distribuciones, no las semillas "
             "una a una.", ""]

    t1, _ = param_table(mat_seeds, c_seeds, "theta_hat",
                        "theta_hat (ajuste con todos los datos)")
    t2, _ = param_table(mat_seeds, c_seeds, "params_median",
                        "Mediana de parametros del ensemble LOO")
    lines += t1 + t2
    lines += band_tables(mat_seeds, c_seeds, truth, times)
    lines += maybe_plots(mat_seeds, c_seeds, os.path.join(here, f"report_{args.model}"))

    report = os.path.join(here, f"report_{args.model}.md")
    with open(report, "w") as f:
        f.write("\n".join(lines))
    print(f"Report written: {report}")
    print("\n".join(lines[:40]))


if __name__ == "__main__":
    main()
