"""Plot the prediction bands written by `cli solve`.

CUQDyn1_Plus builds bands two different ways, so the plot says which is which:
observed states get distribution-free conformal bands from the leave-one-out
ensemble, states that are never measured get Gaussian delta-method bands
propagated through the parameter covariance. When every state is observed the
algorithm reduces to CUQDyn1 and every panel is conformal.
"""

import sys
from pathlib import Path

import matplotlib.pyplot as plt

SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
OBSERVED = "#2a78d6"  # categorical slot 1
UNOBSERVED = "#eb6834"  # categorical slot 2


def read_data(filepath):
    with open(filepath) as f:
        lines = [line.strip() for line in f if line.strip()]

    sections = {}
    i = 0
    while i < len(lines):
        line = lines[i]

        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            i += 1

            dims = list(map(int, lines[i].split(" ")))
            i += 1

            rows = dims[0]
            cols = dims[1] if len(dims) > 1 else 1

            if len(dims) == 1:
                tmp = cols
                cols = rows
                rows = tmp

            matrix = []
            for _ in range(rows):
                values = list(map(float, lines[i].split(" ")))
                assert (
                    len(values) == cols
                ), f"Expected {cols} columns but got {len(values)} for section {section}."
                matrix.append(values if cols > 1 else values[0])
                i += 1

            if not isinstance(matrix[0], (list, tuple)):
                matrix = [[x] for x in matrix]

            sections[section] = {"shape": (rows, cols), "data": matrix}

        else:
            i += 1

    return sections


if len(sys.argv) < 2:
    print("Usage: python plot.py <data_file>")
    sys.exit(1)

data_file = sys.argv[1]

ruta = Path(data_file)
if not ruta.is_file():
    print(f"File {ruta} does not exist.")
    sys.exit(1)

data = read_data(ruta)

q_low = data["Q_low"]["data"]
q_up = data["Q_up"]["data"]
times = data["Times"]["data"][0]

# The leave-one-out median is only in files produced by a full run; the Matlab
# reference dumps carry the bands and the best fit but not the ensemble.
loo_median = data["Data"]["data"] if "Data" in data else None

num_columns = len(q_low[0])

# Written by CUQDyn1_Plus runs; older result files simply have every state observed.
if "ObservedIdx" in data:
    observed = {int(v) for v in data["ObservedIdx"]["data"][0]}
else:
    observed = set(range(num_columns))

media_tot = data["MediaTot"]["data"] if "MediaTot" in data else None

# Only present when the hybrid covariance was used: the plain FIM bands, drawn
# alongside so the two covariance choices can be compared on the hidden states.
fim_low = data["Q_low_fim"]["data"] if "Q_low_fim" in data else None
fim_up = data["Q_up_fim"]["data"] if "Q_up_fim" in data else None

output_folder = ruta.parent

for j in range(num_columns):
    is_observed = j in observed
    color = OBSERVED if is_observed else UNOBSERVED
    kind = (
        "conformal (observado)"
        if is_observed
        else (
            "delta/HybridCov (no observado)"
            if fim_low is not None
            else "delta/FIM (no observado)"
        )
    )

    fig, ax = plt.subplots(figsize=(8, 5), facecolor=SURFACE)
    ax.set_facecolor(SURFACE)

    lower = [row[j] for row in q_low]
    upper = [row[j] for row in q_up]

    ax.fill_between(times, lower, upper, color=color, alpha=0.18, linewidth=0, zorder=2)
    ax.plot(times, lower, color=color, linewidth=2, zorder=4)
    ax.plot(times, upper, color=color, linewidth=2, zorder=4, label=f"banda {kind}")
    if loo_median is not None:
        ax.plot(
            times,
            [row[j] for row in loo_median],
            color=color,
            linewidth=2,
            linestyle=(0, (1, 1.6)),
            zorder=5,
            label="mediana leave-one-out",
        )

    if fim_low is not None and not is_observed:
        ax.plot(
            times,
            [row[j] for row in fim_low],
            color=INK,
            linewidth=1.4,
            linestyle=(0, (5, 2.5)),
            zorder=5,
        )
        ax.plot(
            times,
            [row[j] for row in fim_up],
            color=INK,
            linewidth=1.4,
            linestyle=(0, (5, 2.5)),
            zorder=5,
            label="banda FIM (comparacion)",
        )

    if media_tot is not None:
        ax.plot(
            times,
            [row[j] for row in media_tot],
            color=INK,
            linewidth=1.4,
            zorder=6,
            label="ajuste global",
        )

    ax.set_title(
        f"y{j}  ·  {kind}", color=INK, fontsize=12, fontweight="bold", loc="left"
    )
    ax.set_xlabel("tiempo", color=INK_2)
    ax.set_ylabel("valor", color=INK_2)
    ax.grid(True, color="#e6e5e0", linewidth=0.8, zorder=0)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color("#d5d4ce")
    ax.tick_params(colors=INK_2, length=3, color="#d5d4ce")

    legend = ax.legend(frameon=False, fontsize=9.5)
    for text in legend.get_texts():
        text.set_color(INK_2)

    fig.tight_layout()
    fig.savefig(f"{output_folder}/y{j}.png", dpi=300, facecolor=SURFACE)
    plt.close(fig)

print(f"{num_columns} figure(s) written to {output_folder}")
