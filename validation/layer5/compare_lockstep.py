#!/usr/bin/env python3
"""Layer 5: the C pipeline (MEIGO served by MATLAB) against the MATLAB pipeline.

Both sides ran the same launches (0 = full fit, k = 1..m-1 = leave out t(k+1))
with MEIGO seeded base_seed + k, so their evaluation traces should coincide
until a rounding difference in the cost flips a discrete eSS decision. Per
launch this script reports how long the traces stay identical, how well the
two costs agree on that identical prefix, where the traces first diverge and
whether both still reach the same optimum; then it compares the final
pipeline outputs.

Usage:
    python3 compare_lockstep.py lv2 [--c-dir D] [--matlab-dir D]

Writes report_<model>.md next to this script. Exit code 0 always: a report.
"""

import argparse
import os
import re

import numpy as np

THETA_TOL = 1e-12  # relative: "the same evaluation"
# How far the two CVODES builds (MATLAB's and the fetched one) may disagree on J
# at the same theta: ~1e-9 typically and ~1e-6 at the worst points of a search
# on lv2, ap and sir, but up to ~3e-4 on the stiff nfkb, whose trajectories
# already differ by 5e-4 between integrators (layer2_traj). A wrong data slice
# on either side moves J by ~1/m of its value, orders of magnitude more, so a
# per-model tolerance in common/models/<m>/tol.txt (key layer5_cost) separates
# rounding from an orchestration bug without hiding one.
J_TOL_DEFAULT = 1e-5
OPT_TOL = 1e-4  # relative: "the same optimum"


def read_matrix(path):
    with open(path) as f:
        rows, cols = (int(x) for x in f.readline().split())
        data = np.loadtxt(f)
    return data.reshape(rows, cols)


def read_trace(path):
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return None
    return np.loadtxt(path, ndmin=2)


def parse_c_results(path):
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
        if len(header) == 1:
            n = int(header[0])
            sections[name] = np.array([float(x) for x in lines[i + 2].split()])
            assert len(sections[name]) == n
            i += 3
        else:
            rows, cols = int(header[0]), int(header[1])
            block = [[float(x) for x in lines[i + 2 + r].split()] for r in range(rows)]
            sections[name] = np.array(block)
            i += 2 + rows
    return sections


def cost_tolerance(here, model):
    path = os.path.join(here, "..", "common", "models", model, "tol.txt")
    if os.path.isfile(path):
        with open(path) as f:
            for line in f:
                parts = line.split()
                if len(parts) == 2 and parts[0] == "layer5_cost":
                    return float(parts[1])
    return J_TOL_DEFAULT


def rel(a, b):
    return np.abs(a - b) / np.maximum(np.abs(b), 1e-300)


def compare_launch(k, c_dir, m_dir, j_tol):
    tc = read_trace(os.path.join(c_dir, f"evals_{k}.txt"))
    tm = read_trace(os.path.join(m_dir, f"evals_{k}.txt"))
    oc = read_trace(os.path.join(c_dir, f"theta_{k}.txt"))
    om = read_trace(os.path.join(m_dir, f"theta_{k}.txt"))
    if tc is None or tm is None or oc is None or om is None:
        return {"k": k, "missing": True}
    n = min(len(tc), len(tm))
    same_theta = np.all(rel(tc[:n, :-1], tm[:n, :-1]) <= THETA_TOL, axis=1)
    first_theta = None if same_theta.all() else int(np.argmin(same_theta))
    prefix = n if first_theta is None else first_theta
    j_rel = rel(tc[:prefix, -1], tm[:prefix, -1]) if prefix > 0 else np.zeros(0)
    bad = np.where(j_rel > j_tol)[0]
    return {
        "k": k,
        "missing": False,
        "n_c": len(tc),
        "n_m": len(tm),
        "prefix": prefix,
        "first_flip": first_theta,
        "j_median": float(np.median(j_rel)) if prefix else 0.0,
        "j_max": float(j_rel.max()) if prefix else 0.0,
        "first_cost_mismatch": int(bad[0]) if len(bad) else None,
        "opt_rel": float(rel(oc[0, :-1], om[0, :-1]).max()),
        "j_c": float(oc[0, -1]),
        "j_m": float(om[0, -1]),
    }


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("model", choices=["lv2", "ap", "sir", "nfkb"])
    ap.add_argument(
        "--c-dir", default=None, help="default: validation/layer5/c/<model>"
    )
    ap.add_argument(
        "--matlab-dir", default=None, help="default: validation/layer5/matlab/<model>"
    )
    args = ap.parse_args()
    c_dir = args.c_dir or os.path.join(here, "c", args.model)
    m_dir = args.matlab_dir or os.path.join(here, "matlab", args.model)

    times = read_matrix(
        os.path.join(here, "..", "common", "models", args.model, "times.txt")
    ).ravel()
    m = len(times)

    j_tol = cost_tolerance(here, args.model)
    rows = [compare_launch(k, c_dir, m_dir, j_tol) for k in range(m)]
    lines = [
        f"# Layer 5 - {args.model}: C pipeline with MATLAB's MEIGO vs the MATLAB pipeline",
        "",
    ]
    lines += [
        "| launch | evals C | evals MATLAB | identical prefix | cost agreement on the prefix (median / max rel) "
        "| first flip | same optimum (max rel) | J C | J MATLAB | verdict |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    n_lock, n_same_opt, n_diff_opt, n_bug, n_missing = 0, 0, 0, 0, 0
    all_j = []
    for r in rows:
        if r["missing"]:
            n_missing += 1
            lines.append(
                f"| {r['k']} | - | - | - | - | - | - | - | - | missing trace |"
            )
            continue
        all_j.append(r["j_max"])
        if r["first_cost_mismatch"] is not None:
            verdict = (
                f"**COST MISMATCH at eval {r['first_cost_mismatch']} on the identical prefix "
                f"- orchestration bug**"
            )
            n_bug += 1
        elif r["first_flip"] is None and r["n_c"] == r["n_m"]:
            verdict = "lock-step"
            n_lock += 1
        elif r["opt_rel"] <= OPT_TOL:
            verdict = "flipped, same optimum"
            n_same_opt += 1
        else:
            verdict = "**flipped, different optimum**"
            n_diff_opt += 1
        flip = "-" if r["first_flip"] is None else str(r["first_flip"])
        lines.append(
            f"| {r['k']} | {r['n_c']} | {r['n_m']} | {r['prefix']} | {r['j_median']:.1e} / {r['j_max']:.1e} "
            f"| {flip} | {r['opt_rel']:.2e} | {r['j_c']:.10g} | {r['j_m']:.10g} | {verdict} |"
        )
    lines += [
        "",
        f"Launches: {m}. Lock-step: {n_lock}. Flipped but same optimum: {n_same_opt}. "
        f"Different optimum: {n_diff_opt}. Cost mismatch on an identical prefix: **{n_bug}**. "
        f"Missing: {n_missing}. Worst cost disagreement on any identical prefix: "
        f"{max(all_j) if all_j else float('nan'):.2e} (tolerance {j_tol:.0e}, layer5_cost in tol.txt).",
        "",
        "A launch is *lock-step* when both sides evaluated the same sequence to the end; it *flipped* "
        "when a rounding-level cost difference made eSS take a different discrete decision, after "
        f"which only the optimum is compared (tolerance {OPT_TOL:.0e} relative). A cost mismatch while "
        "the two sides were still evaluating the same theta means the C side computed a different "
        "objective for that launch: the held-out point, the data slice or the weights.",
        "",
    ]

    c_res = os.path.join(c_dir, "cuqdyn-results.txt")
    if os.path.isfile(c_res) and os.path.isfile(os.path.join(m_dir, "q_up.txt")):
        c = parse_c_results(c_res)
        pairs = [
            (
                "theta_hat",
                c["ParamsInit"],
                read_matrix(os.path.join(m_dir, "theta_hat.txt")).ravel(),
            ),
            (
                "params_median",
                c["Params"],
                read_matrix(os.path.join(m_dir, "params_median.txt")).ravel(),
            ),
            ("q_low", c["Q_low"], read_matrix(os.path.join(m_dir, "q_low.txt"))),
            ("q_up", c["Q_up"], read_matrix(os.path.join(m_dir, "q_up.txt"))),
        ]
        if "CovP" in c:
            pairs.append(
                ("cov_p", c["CovP"], read_matrix(os.path.join(m_dir, "cov_p.txt")))
            )
        if "StdY" in c:
            pairs.append(
                ("std_y", c["StdY"], read_matrix(os.path.join(m_dir, "std_y.txt")))
            )
        lines += ["## Final outputs", "", "| quantity | max scaled diff |", "|---|---|"]
        for name, a, b in pairs:
            scale = max(float(np.abs(b).max()), 1e-300)
            lines.append(f"| {name} | {float(np.abs(a - b).max()) / scale:.3e} |")
        lines.append("")
        lines.append(
            "Scaled by the largest magnitude of the MATLAB array, like the layer-2/4 checks."
        )
    else:
        lines.append("Final outputs not compared: one side has no results yet.")

    report = os.path.join(here, f"report_{args.model}.md")
    with open(report, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"Report written: {report}")


if __name__ == "__main__":
    main()
