#!/usr/bin/env python3
"""Describe the C side of a problem as plain "key value..." lines.

    problem_info.py <cuqdyn.xml> <sacess.xml> <data.txt> [name]
    problem_info.py --set-budget N <sacess.xml> <copy.xml>

The three files are the ones the CLI takes (-c, -s, -d). The output is the
single hand-over between the two sides of the validation: run_validation.sh
writes it to <output_dir>/<layer>/<name>/settings.txt, the MATLAB loader
(matlab/load_problem.m) takes its run settings from it - alpha, the integration
tolerances, the eSS budget - and checks everything both sides define twice
against it (sizes, bounds, initial point, initial condition, time grid, observed
states, sigma).

The second form copies a sacess XML with <maxevaluation> replaced, for smoke
runs: the copy is what both sides then read their budget from.

Only the standard library is used, so the script runs wherever the CLI does.
"""

import math
import re
import sys
import xml.etree.ElementTree as ET


def numbers(text):
    """The comma/whitespace separated numbers of an XML text node."""
    return [float(tok) for tok in text.replace(",", " ").split()]


def fmt(values):
    return " ".join(repr(float(v)) for v in values)


def text_of(root, path, default=None):
    node = root.find(path)
    if node is None or node.text is None or not node.text.strip():
        return default
    return node.text.strip()


def read_data(path):
    """The CLI's data format: "rows cols" header, then t y1 .. yn per row."""
    with open(path, encoding="utf-8") as handle:
        tokens = handle.read().split()
    rows, cols = int(tokens[0]), int(tokens[1])
    flat = [float(tok) for tok in tokens[2 : 2 + rows * cols]]
    if len(flat) != rows * cols:
        raise ValueError(f"{path}: expected {rows}x{cols} values, found {len(flat)}")
    return [flat[i * cols : (i + 1) * cols] for i in range(rows)]


def set_budget(budget, source, target):
    with open(source, encoding="utf-8") as handle:
        text = handle.read()
    text, count = re.subn(
        r"<maxevaluation>[^<]*</maxevaluation>",
        f"<maxevaluation>{int(float(budget))}</maxevaluation>",
        text,
    )
    if count != 1:
        sys.exit(f"{source}: expected one <maxevaluation>, found {count}")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(text)


def main(argv):
    if len(argv) == 5 and argv[1] == "--set-budget":
        set_budget(argv[2], argv[3], argv[4])
        return
    if len(argv) not in (4, 5):
        sys.exit(__doc__)
    cuqdyn_xml, sacess_xml, data_file = argv[1:4]

    conf = ET.parse(cuqdyn_xml).getroot()
    ess = ET.parse(sacess_xml).getroot()
    data = read_data(data_file)

    ode = conf.find("ode_expr")
    n_states = int(ode.get("y_count"))
    n_params = int(ode.get("p_count"))
    if len(data[0]) != n_states + 1:
        sys.exit(
            f"{data_file}: {len(data[0]) - 1} state columns, the XML declares {n_states}"
        )

    # A state is observed iff its column is finite for every t > 0 (README,
    # "Partial observability"); a column mixing NaN and values is an error in
    # the CLI too.
    observed = []
    for j in range(1, n_states + 1):
        column = [row[j] for row in data[1:]]
        missing = sum(math.isnan(v) for v in column)
        if missing == 0:
            observed.append(j)
        elif missing != len(column):
            sys.exit(f"{data_file}: state {j} mixes NaN with values")

    out = []
    if len(argv) == 5:
        out.append(f"name {argv[4]}")
    out.append(f"n_states {n_states}")
    out.append(f"n_params {n_params}")
    out.append(f"m {len(data)}")
    out.append("times " + fmt(row[0] for row in data))
    out.append("y0 " + fmt(data[0][1:]))
    out.append("observed_idx " + " ".join(str(j) for j in observed))  # 1-based

    out.append("alp " + repr(float(text_of(conf, "alp", "0.05"))))
    out.append("uq_method " + text_of(conf, "uq_method", "fim"))
    out.append("rtol " + repr(float(text_of(conf, "tolerances/rtol"))))
    out.append("atol " + fmt(numbers(text_of(conf, "tolerances/atol"))))
    out.append("residual_model " + text_of(conf, "cost/residual_model", "none"))
    sigma = text_of(conf, "cost/sigma")
    if sigma is not None:
        out.append("sigma " + fmt(numbers(sigma)))

    out.append(
        "maxeval "
        + str(int(float(text_of(ess, "run/stopping_criteria/maxevaluation"))))
    )
    out.append("log_scale " + text_of(ess, "run/log_scale", "0"))
    out.append("local_solver " + text_of(ess, "method/local_options/solver", "default"))
    out.append("local_tol " + text_of(ess, "method/local_options/tol", "default"))
    for key, tag in (("lb", "lb"), ("ub", "ub"), ("x0", "point")):
        values = numbers(text_of(ess, f"problem/{tag}"))
        if len(values) != n_params:
            sys.exit(
                f"{sacess_xml}: <{tag}> has {len(values)} values, p_count is {n_params}"
            )
        out.append(f"{key} " + fmt(values))

    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv)
