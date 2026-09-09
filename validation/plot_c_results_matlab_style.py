#!/usr/bin/env python3
"""Render a C cuqdyn-results.txt with the same layout as MATLAB's plot_hybrid_uq.

    python3 plot_c_results_matlab_style.py <cuqdyn-results.txt> <data_file.txt> [out.png]

One subplot per state, side by side: shaded 95% band, best fit (solid for
observed states, dashed for hidden ones), data markers for observed states.
Negative lower bands are clamped to zero, exactly like the MATLAB plotter, so
the two figures can be compared panel by panel without cosmetic differences.
"""

import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

# Same hues as MATLAB's default axes order (and the repo's plot.py).
OBSERVED = "#2a78d6"
UNOBSERVED = "#eb6834"
INK = "#0b0b0b"
INK_2 = "#52514e"
GRID = "#d5d4ce"


def read_sections(path):
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    sections = {}
    i = 0
    while i < len(lines):
        if lines[i].startswith("[") and lines[i].endswith("]"):
            name = lines[i][1:-1]
            dims = list(map(int, lines[i + 1].split()))
            i += 2
            if len(dims) == 1:  # vector: one line of values
                sections[name] = np.array([float(x) for x in lines[i].split()])
                i += 1
            else:
                rows = dims[0]
                block = [[float(x) for x in lines[i + r].split()] for r in range(rows)]
                sections[name] = np.array(block)
                i += rows
        else:
            i += 1
    return sections


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    results = read_sections(sys.argv[1])
    out = sys.argv[3] if len(sys.argv) > 3 else "c_hybrid_uq_plot.png"

    # Raw measurements: "m n" header then time + one column per state (NaN = hidden).
    raw = np.loadtxt(sys.argv[2], skiprows=1)
    t_data, y_data = raw[:, 0], raw[:, 1:]

    times = results["Times"]
    media_tot = results["MediaTot"]  # m x n_states
    q_low = np.maximum(results["Q_low"], 0.0)  # clamp like MATLAB
    q_up = results["Q_up"]
    observed = set(int(v) for v in np.atleast_1d(results["ObservedIdx"]))
    n_states = media_tot.shape[1]

    coverage = 95  # 1 - 2*alp with alp = 0.025
    fig, axes = plt.subplots(
        1, n_states, figsize=(5.6 * n_states + 0.6, 4.4), facecolor="white"
    )
    axes = np.atleast_1d(axes)

    for j, ax in enumerate(axes):
        is_obs = j in observed
        c = OBSERVED if is_obs else UNOBSERVED

        ax.fill_between(
            times, q_low[:, j], q_up[:, j], color=c, alpha=0.22, linewidth=0,
            label=f"{coverage}% PI",
        )
        ax.plot(
            times, media_tot[:, j], color=c, linewidth=2,
            linestyle="-" if is_obs else (0, (5, 3)), label="best fit",
        )
        if is_obs:
            mask = np.isfinite(y_data[:, j])
            ax.plot(
                t_data[mask], y_data[mask, j], "o", markersize=6,
                markerfacecolor="white", markeredgecolor=INK, markeredgewidth=1,
                linestyle="none", label="data",
            )

        kind = "observed" if is_obs else "unobserved"
        ax.set_title(f"State {j + 1} ({kind}) - {coverage}% PI", color=INK, fontsize=12,
                     fontweight="bold")
        ax.set_xlabel("Time", color=INK_2)
        ax.set_ylabel("Value", color=INK_2)
        ax.grid(True, color=GRID, linewidth=0.7)
        ax.set_axisbelow(True)
        for side in ("top", "right"):
            ax.spines[side].set_visible(False)
        for side in ("left", "bottom"):
            ax.spines[side].set_color(GRID)
        ax.tick_params(colors=INK_2, length=3, color=GRID)
        legend = ax.legend(frameon=False, fontsize=9.5, loc="upper right")
        for text in legend.get_texts():
            text.set_color(INK_2)

    fig.suptitle("CUQDyn-C - prediction bands", color=INK, fontsize=14, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.95))
    fig.savefig(out, dpi=200, facecolor="white")
    print(f"Figure written: {out}")


if __name__ == "__main__":
    main()
