from __future__ import annotations

import csv
import math
import shutil
from collections import defaultdict
from datetime import datetime
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
PYMC_DIR = REPO / "pymc_matlab"
COMPARISON_ROOT = PYMC_DIR / "results" / "comparison"
RUN_DATE = datetime.now().strftime("%Y-%m-%d")
REPORT_DIR = REPO / "REPORTS" / f"CUQDyn_vs_PyMC_comparison_{RUN_DATE}"
FIG_DIR = REPORT_DIR / "figures"


MODEL_SETTINGS = [
    {
        "model": "LV",
        "data": "EXAMPLES/LV/data/lv2_synthetic_data_noi10_partobs_1.csv",
        "states": "prey, predator",
        "observed": "prey",
        "noise": "10% synthetic observation noise",
        "parameters": "alpha=0.5, beta=0.02, delta=0.02, gamma=0.5",
        "notes": "Predator is hidden after t=0; all methods use the same CSV.",
    },
    {
        "model": "SIR",
        "data": "EXAMPLES/SIR/data/sir_data.csv",
        "states": "susceptible, infected, recovered",
        "observed": "infected",
        "noise": "10% proportional synthetic noise on infected state",
        "parameters": "beta=0.002, gamma=0.5",
        "notes": "Susceptible and recovered are hidden after t=0.",
    },
    {
        "model": "AP",
        "data": "EXAMPLES/AP/data/AP_measurementData_1_4.csv",
        "states": "y1, y2, y3, y4, y5",
        "observed": "y1-y4",
        "noise": "alpha-pinene measurement dataset used by CUQDyn examples",
        "parameters": "p1=5.93e-05, p2=2.96e-05, p3=2.05e-05, p4=2.75e-04, p5=4.00e-05",
        "notes": "y5 is hidden after t=0; AP residuals/PyMC ABC distance normalize observed states by scale.",
    },
    {
        "model": "NFKB",
        "data": "EXAMPLES/NFKB/data/NFKB_synthetic_data_5n_36st_partobs10.csv",
        "states": "15-state NF-kB signaling model",
        "observed": "y1, y2, y3, y5, y7, y9, y11, y12, y13, y15",
        "noise": "5% synthetic noise, 36 sampling times",
        "parameters": "29 kinetic parameters p1-p29; nominal values from run_bayes_nfkb.m",
        "notes": "Five states are hidden: y4, y6, y8, y10, y14.",
    },
]


PYMC_SETTINGS = [
    {
        "model": "LV",
        "priors": "Uniform: alpha [0.10,1.00], beta/delta [0.004,0.04], gamma [0.10,1.00]",
        "distance": "PyMC Simulator ABC distance on observed prey",
        "epsilon": "3",
        "draws": "4000 x 4 chains",
        "thresholds": "threshold=0.6, correlation_threshold=0.01",
        "trajectory_samples": "500 posterior draws; observed-state export includes RMSE noise augmentation",
    },
    {
        "model": "SIR",
        "priors": "Uniform: beta [1e-4,1e-2], gamma [0.01,2.0]",
        "distance": "PyMC Simulator ABC distance on infected state",
        "epsilon": "20",
        "draws": "1000 x 4 chains",
        "thresholds": "threshold=0.3, correlation_threshold=0.1",
        "trajectory_samples": "500 posterior draws; observed-state export includes RMSE noise augmentation",
    },
    {
        "model": "AP",
        "priors": "Uniform bounds equal nominal parameter value times [0.05,5.0], matching current CUQDyn AP runs",
        "distance": "ABC distance on y1-y4 after dividing each state by its time mean",
        "epsilon": "0.5",
        "draws": "1000 x 4 chains",
        "thresholds": "threshold=0.5, correlation_threshold=0.1",
        "trajectory_samples": "500 posterior draws; observed-state export includes RMSE noise augmentation",
    },
    {
        "model": "NFKB",
        "priors": "Uniform bounds equal nominal parameter value times [0.1,4.0], matching current CUQDyn NF-kB support",
        "distance": "custom normalized L1 distance over observed states, each scaled by observed maximum",
        "epsilon": "1.0",
        "draws": "1000 x 4 chains",
        "thresholds": "threshold=0.3, correlation_threshold=0.1; 1000-draw comparison run is flagged if R-hat > 1.01 or ESS < 100 x chains",
        "trajectory_samples": "500 posterior draws; observed-state export includes RMSE noise augmentation; independent 4000-draw rerun passes the gate marginally but remains prior-dominated",
    },
]


CUQDYN_SETTINGS = {
    "CUQDyn1_Plus FIM": {
        "description": "best-fit trajectory with FIM/delta-method parameter covariance propagated to prediction bands",
        "optimizer": "MEIGO/eSS global fit with lsqnonlin local solver, example-specific maxeval from run script",
        "uq": "nominal 95% bands with alp=0.025 in current examples",
    },
    "CUQDyn1_Plus HybridCov": {
        "description": "same CUQDyn fit workflow, replacing FIM correlations with LOO-refit correlations while retaining FIM marginal scale",
        "optimizer": "MEIGO/eSS global fit with LOO refits according to example options",
        "uq": "nominal 95% HybridCov bands with alp=0.025",
    },
}


def latest_comparison_dir() -> Path:
    candidates = [p for p in COMPARISON_ROOT.iterdir() if p.is_dir()]
    if not candidates:
        raise FileNotFoundError(f"No comparison folders found in {COMPARISON_ROOT}")
    return max(candidates, key=lambda p: p.stat().st_mtime)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def tex_escape(value: object) -> str:
    s = "" if value is None else str(value)
    repl = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        # allow long paths/identifiers to wrap inside narrow table cells
        # instead of overflowing into the neighbouring column
        "_": r"\_\allowbreak{}",
        "/": r"/\allowbreak{}",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    return "".join(repl.get(ch, ch) for ch in s)


def num(value: str | float | None, digits: int = 3) -> str:
    if value in (None, "", "NaN", "nan"):
        return "--"
    x = float(value)
    if not math.isfinite(x):
        return "--"
    if x == 0:
        return "0"
    ax = abs(x)
    if ax < 1e-3 or ax >= 1e4:
        return f"{x:.{digits}e}"
    return f"{x:.{digits}g}"


def pct(value: str | float | None) -> str:
    if value in (None, "", "NaN", "nan"):
        return "--"
    x = float(value)
    if not math.isfinite(x):
        return "--"
    return f"{x:.1f}"


def table(
    headers: list[str],
    rows: list[list[object]],
    widths: str | None = None,
    font_size: str | None = None,
) -> str:
    colspec = widths if widths else "l" * len(headers)
    out = [r"\begin{longtable}{" + colspec + "}", r"\toprule"]
    out.append(" & ".join(tex_escape(h) for h in headers) + r" \\")
    out.append(r"\midrule")
    out.append(r"\endfirsthead")
    out.append(r"\toprule")
    out.append(" & ".join(tex_escape(h) for h in headers) + r" \\")
    out.append(r"\midrule")
    out.append(r"\endhead")
    for row in rows:
        out.append(" & ".join(tex_escape(v) for v in row) + r" \\")
    out.append(r"\bottomrule")
    out.append(r"\end{longtable}")
    body = "\n".join(out)
    if font_size:
        return "{%\n" + font_size + "\n" + r"\setlength{\tabcolsep}{2.5pt}" + "\n" + body + "\n}"
    return body


def grouped(rows: list[dict[str, str]], key: str) -> dict[str, list[dict[str, str]]]:
    out: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        out[row[key]].append(row)
    return dict(out)


def aggregate_band_rows(bands: list[dict[str, str]]) -> list[list[str]]:
    grouped_rows = defaultdict(list)
    for row in bands:
        grouped_rows[(row["Model"], row["Method"])].append(row)
    output = []
    for (model, method), rows in sorted(grouped_rows.items()):
        observed = [r for r in rows if r["ObservedCoveragePercent"] not in ("", "NaN", "nan")]
        hidden = [r for r in rows if r["ObservedCoveragePercent"] in ("", "NaN", "nan")]
        covs = [float(r["ObservedCoveragePercent"]) for r in observed]
        rmses = [float(r["RMSEObservedStates"]) for r in observed if r["RMSEObservedStates"] not in ("", "NaN", "nan")]
        obs_width = [float(r["MeanBandWidth"]) for r in observed]
        hid_width = [float(r["MeanBandWidth"]) for r in hidden]
        output.append([
            model,
            method,
            str(len(observed)),
            pct(sum(covs) / len(covs) if covs else None),
            num(sum(rmses) / len(rmses) if rmses else None),
            num(sum(obs_width) / len(obs_width) if obs_width else None),
            str(len(hidden)),
            num(sum(hid_width) / len(hid_width) if hid_width else None),
        ])
    return output


def aggregate_parameter_rows(params: list[dict[str, str]]) -> list[list[str]]:
    grouped_rows = defaultdict(list)
    for row in params:
        grouped_rows[(row["Model"], row["Method"])].append(row)
    output = []
    for (model, method), rows in sorted(grouped_rows.items()):
        rel = [float(r["RelErrPercent"]) for r in rows if r["RelErrPercent"] not in ("", "NaN", "nan")]
        rel_sorted = sorted(rel)
        median = rel_sorted[len(rel_sorted) // 2] if rel_sorted else math.nan
        under20 = sum(x <= 20 for x in rel)
        output.append([
            model,
            method,
            str(len(rows)),
            pct(sum(rel) / len(rel) if rel else None),
            pct(median),
            f"{under20}/{len(rel)}" if rel else "--",
        ])
    return output


def lookup_aggregate(rows: list[list[str]], model: str, method: str, column: int) -> str:
    for row in rows:
        if row[0] == model and row[1] == method:
            return row[column]
    return "--"


def detailed_discussion(params: list[dict[str, str]], bands: list[dict[str, str]]) -> str:
    p_agg = aggregate_parameter_rows(params)
    b_agg = aggregate_band_rows(bands)
    return "\n".join([
        r"\section{Detailed Discussion of the Updated Comparison}",
        "The PyMC workflows used for the shared comparison tables were rerun after harmonizing several settings that materially affect the comparison: LV and SIR now use tighter ODE tolerances inside the ABC simulator; SIR, AP, and the tabulated NF-kB comparison use 1000 SMC draws per chain, while LV uses 4000 draws per chain; AP priors now match the widened CUQDyn AP parameter bounds; and all PyMC examples export 500 trajectory samples. For observed states, the exported PyMC predictive trajectories now include an additive observation-noise term estimated from the RMSE of the posterior mean against the observed data. Hidden-state PyMC bands remain latent parameter-uncertainty bands. An independent follow-up NF-kB PyMC rerun with 4000 draws per chain is discussed below as a convergence sensitivity check, not as a replacement for the tabulated comparison CSVs.",
        "",
        r"\paragraph{LV.}",
        f"LV shows strong agreement between PyMC and CUQDyn. The mean parameter relative error is {lookup_aggregate(p_agg, 'LV', 'PyMC ABC-SMC', 3)}\\% for PyMC and about {lookup_aggregate(p_agg, 'LV', 'CUQDyn1_Plus FIM', 3)}\\% for CUQDyn FIM, with all four parameters within 20\\% relative error for all methods. Observed prey coverage is {lookup_aggregate(b_agg, 'LV', 'PyMC ABC-SMC', 3)}\\% for PyMC and 100\\% for CUQDyn. PyMC gives a narrower observed-state band than CUQDyn, while the hidden predator band is somewhat wider on average. This is a well-behaved case where both methods tell the same practical story.",
        "",
        r"\paragraph{SIR.}",
        f"SIR is the clearest agreement case. PyMC and CUQDyn recover beta and gamma with mean relative errors below 1\\%: {lookup_aggregate(p_agg, 'SIR', 'PyMC ABC-SMC', 3)}\\% for PyMC and {lookup_aggregate(p_agg, 'SIR', 'CUQDyn1_Plus FIM', 3)}\\% for CUQDyn FIM. The infected-state RMSE is essentially identical across methods, and all methods give 100\\% observed-state coverage. The PyMC hidden-state bands are wider than CUQDyn bands, reflecting posterior sampling plus the ABC tolerance, but the central trajectories and observed-state uncertainty are highly consistent.",
        "",
        r"\paragraph{AP.}",
        f"AP remains more sensitive to prior/bound choices. After widening the PyMC AP priors to match CUQDyn, PyMC's mean parameter relative error increases to {lookup_aggregate(p_agg, 'AP', 'PyMC ABC-SMC', 3)}\\%, driven mostly by p4 and p5. CUQDyn FIM and HybridCov remain around {lookup_aggregate(p_agg, 'AP', 'CUQDyn1_Plus FIM', 3)}\\% mean relative error. However, the trajectory comparison is much closer than the raw parameter errors suggest: PyMC observed-state coverage averages {lookup_aggregate(b_agg, 'AP', 'PyMC ABC-SMC', 3)}\\%, CUQDyn gives 100\\%, and the observed-state RMSE values are of the same order. This indicates practical sloppiness/non-identifiability in AP: distinct parameter combinations can generate similar observed y1-y4 dynamics, especially when y5 is hidden.",
        "",
        r"\paragraph{NF-kB.}",
        f"NF-kB remains the stress test and should not be presented as a clean parameter-recovery success. In the 1000-draw comparison run, PyMC has mean parameter relative error {lookup_aggregate(p_agg, 'NFKB', 'PyMC ABC-SMC', 3)}\\%, compared with CUQDyn FIM at {lookup_aggregate(p_agg, 'NFKB', 'CUQDyn1_Plus FIM', 3)}\\% and HybridCov at {lookup_aggregate(p_agg, 'NFKB', 'CUQDyn1_Plus HybridCov', 3)}\\%. The current PyMC NF-kB workflow uses the same broad support as CUQDyn rather than a prior centred on the answer, but the 1000-draw run fails the standard R-hat/ESS gate. A follow-up 4000-draw rerun improves sampler diagnostics to a marginal pass (max R-hat about 1.01, min bulk ESS about 503), showing that the sampling issue can be reduced by more draws. However, the posterior means remain close to the broad-prior mean, approximately two times the nominal values for many rates. Thus convergence does not imply identifiability: these parameter summaries are diagnostic of weak or structural non-identifiability, not trustworthy parameter estimates. CUQDyn gives much lower observed-state RMSE on average, whereas PyMC's observed RMSE is dominated by y11. After noise augmentation, PyMC observed-state coverage is high ({lookup_aggregate(b_agg, 'NFKB', 'PyMC ABC-SMC', 3)}\\%), but some hidden-state PyMC bands are very wide, especially y8, y10, and y11-related dynamics. CUQDyn hidden-state bands should be interpreted together with the FIM rank and reliability diagnostics in this high-dimensional, partially observed system.",
        "",
        r"\paragraph{Overall conclusion.}",
        "For LV and SIR, the methods agree closely in both parameter recovery and predictive behavior. For AP, the predictive agreement is better than the parameter agreement, which is consistent with partial observation and parameter compensation. For NF-kB, the 1000-draw PyMC comparison run is not fully converged; a 4000-draw sensitivity rerun can pass the R-hat/ESS gate marginally, but the posterior remains prior-dominated. NF-kB rate constants should therefore not be reported as recovered. The comparison is most meaningful at the level of observed trajectory fit, posterior predictive coverage, FIM reliability diagnostics, convergence diagnostics, and qualitative hidden-state uncertainty rather than one-to-one parameter intervals.",
    ])


def copy_figures(comp_dir: Path) -> list[tuple[str, Path]]:
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    copied = []
    patterns = [
        ("LV", "lv_cuqdyn_vs_pymc_side_by_side.png"),
        ("SIR", "sir_cuqdyn_vs_pymc_side_by_side.png"),
        ("AP", "ap_cuqdyn_vs_pymc_side_by_side.png"),
        ("NFKB states 1-5", "nfkb_cuqdyn_vs_pymc_side_by_side_states01_05.png"),
        ("NFKB states 6-10", "nfkb_cuqdyn_vs_pymc_side_by_side_states06_10.png"),
        ("NFKB states 11-15", "nfkb_cuqdyn_vs_pymc_side_by_side_states11_15.png"),
    ]
    for label, filename in patterns:
        src = comp_dir / filename
        if src.is_file():
            dest = FIG_DIR / src.name
            shutil.copy2(src, dest)
            for suffix in [".pdf", ".eps"]:
                sibling = src.with_suffix(suffix)
                if sibling.is_file():
                    shutil.copy2(sibling, FIG_DIR / sibling.name)
            copied.append((label, Path("figures") / dest.name))
    return copied


def latest_result_dirs() -> list[list[str]]:
    rows = []
    patterns = [
        ("LV", "CUQDyn1_Plus FIM", REPO / "EXAMPLES" / "LV", "Results_LV2_CUQDyn1_Plus_*"),
        ("LV", "CUQDyn1_Plus HybridCov", REPO / "EXAMPLES" / "LV", "Results_LV2_HybridCov_*"),
        ("SIR", "CUQDyn1_Plus FIM", REPO / "EXAMPLES" / "SIR", "Results_SIR_CUQDyn1Plus_*"),
        ("SIR", "CUQDyn1_Plus HybridCov", REPO / "EXAMPLES" / "SIR", "Results_SIR_HybridCov_*"),
        ("AP", "CUQDyn1_Plus FIM", REPO / "EXAMPLES" / "AP", "Results_AP_partobs1_4_*"),
        ("AP", "CUQDyn1_Plus HybridCov", REPO / "EXAMPLES" / "AP", "Results_AP_HybridCov_partobs1_4_*"),
        ("NFKB", "CUQDyn1_Plus FIM", REPO / "EXAMPLES" / "NFKB", "Results_NFKB_*"),
        ("NFKB", "CUQDyn1_Plus HybridCov", REPO / "EXAMPLES" / "NFKB", "Results_NFKB_*"),
    ]
    needed = {
        "CUQDyn1_Plus FIM": "CUQDyn1_Plus_results.mat",
        "CUQDyn1_Plus HybridCov": "CUQDyn1_Plus_HybridCov_results.mat",
    }
    for model, method, parent, pattern in patterns:
        dirs = [p for p in parent.glob(pattern) if p.is_dir() and (p / needed[method]).is_file()]
        latest = max(dirs, key=lambda p: p.stat().st_mtime) if dirs else None
        rows.append([model, method, str(latest.relative_to(REPO)) if latest else "not found"])
    for model in ["lv", "sir", "ap", "nfkb"]:
        rows.append([model.upper(), "PyMC ABC-SMC", f"pymc_matlab/results/{model}"])
    return rows


def make_report() -> Path:
    comp_dir = latest_comparison_dir()
    params = read_csv(comp_dir / "parameter_summary_comparison.csv")
    bands = read_csv(comp_dir / "trajectory_band_summary_comparison.csv")

    if REPORT_DIR.exists():
        shutil.rmtree(REPORT_DIR)
    REPORT_DIR.mkdir(parents=True)
    figures = copy_figures(comp_dir)

    shutil.copy2(comp_dir / "parameter_summary_comparison.csv", REPORT_DIR / "parameter_summary_comparison.csv")
    shutil.copy2(comp_dir / "trajectory_band_summary_comparison.csv", REPORT_DIR / "trajectory_band_summary_comparison.csv")

    lines: list[str] = []
    lines.extend([
        r"\documentclass[11pt]{article}",
        r"\usepackage[margin=0.85in]{geometry}",
        r"\usepackage{graphicx}",
        r"\usepackage{booktabs}",
        r"\usepackage{longtable}",
        r"\usepackage{array}",
        r"\usepackage{pdflscape}",
        r"\usepackage{hyperref}",
        r"\usepackage{caption}",
        r"\usepackage{xcolor}",
        r"\setlength{\tabcolsep}{3pt}",
        r"\renewcommand{\arraystretch}{1.08}",
        r"\setlength{\LTpre}{4pt}",
        r"\setlength{\LTpost}{8pt}",
        r"\title{CUQDyn1\_Plus versus PyMC ABC-SMC Comparison Report}",
        rf"\date{{Generated {datetime.now():%Y-%m-%d %H:%M}}}",
        r"\begin{document}",
        r"\maketitle",
        r"\tableofcontents",
        r"\clearpage",
        r"\section{Scope and Provenance}",
        "This report compares the latest completed CUQDyn1\\_Plus and PyMC ABC-SMC outputs for the maintained Bayesian comparison examples: LV, SIR, AP, and NF-kB. The tables are generated from the shared comparison CSV files produced by \\texttt{pymc\\_matlab/compare\\_cuqdyn\\_pymc.m}. The PyMC workflows read the same data CSV files used by the corresponding CUQDyn examples.",
        "",
        f"Comparison source folder: \\texttt{{{tex_escape(str(comp_dir.relative_to(REPO)))}}}.",
        "",
        r"\begin{landscape}",
        r"\section{Example Settings}",
        table(
            ["Model", "Data CSV", "States", "Observed states", "Noise/data model", "True/nominal parameters", "Notes"],
            [[m["model"], m["data"], m["states"], m["observed"], m["noise"], m["parameters"], m["notes"]] for m in MODEL_SETTINGS],
            r"p{0.06\linewidth}p{0.17\linewidth}p{0.12\linewidth}p{0.12\linewidth}p{0.13\linewidth}p{0.20\linewidth}p{0.12\linewidth}",
            r"\scriptsize",
        ),
        r"\section{Method Settings}",
        r"\subsection{CUQDyn1\_Plus Settings}",
        table(
            ["Method", "Summary", "Optimizer/refits", "Uncertainty setting"],
            [[method, info["description"], info["optimizer"], info["uq"]] for method, info in CUQDYN_SETTINGS.items()],
            r"p{0.16\linewidth}p{0.30\linewidth}p{0.28\linewidth}p{0.18\linewidth}",
            r"\scriptsize",
        ),
        "For each model and method, the latest timestamped result folder containing the expected CUQDyn result MAT file was used:",
        table(["Model", "Method", "Result folder"], latest_result_dirs(), r"p{0.07\linewidth}p{0.20\linewidth}p{0.66\linewidth}", r"\scriptsize"),
        r"\subsection{PyMC ABC-SMC Settings}",
        table(
            ["Model", "Priors", "Distance/normalization", "epsilon", "draws/chains", "SMC thresholds", "Trajectory ensemble"],
            [[m["model"], m["priors"], m["distance"], m["epsilon"], m["draws"], m["thresholds"], m["trajectory_samples"]] for m in PYMC_SETTINGS],
            r"p{0.06\linewidth}p{0.22\linewidth}p{0.25\linewidth}p{0.06\linewidth}p{0.10\linewidth}p{0.14\linewidth}p{0.10\linewidth}",
            r"\scriptsize",
        ),
        "PyMC trajectory bands in this report are quantiles of the exported posterior trajectory ensembles. Observed-state PyMC bands include an additive observation-noise term estimated from posterior-mean RMSE; hidden-state PyMC bands remain latent parameter-uncertainty bands.",
        r"\end{landscape}",
        r"\clearpage",
        r"\section{High-Level Parameter Comparison}",
        table(
            ["Model", "Method", "n params", "Mean rel. err. %", "Median rel. err. %", "Params <=20% rel. err."],
            aggregate_parameter_rows(params),
            r"p{0.08\linewidth}p{0.26\linewidth}rrrr",
            r"\small",
        ),
        r"\section{High-Level Trajectory-Band Comparison}",
        table(
            ["Model", "Method", "Observed states", "Mean observed coverage %", "Mean observed RMSE", "Mean observed band width", "Hidden states", "Mean hidden band width"],
            aggregate_band_rows(bands),
            r"p{0.07\linewidth}p{0.25\linewidth}rrrrrr",
            r"\scriptsize",
        ),
        r"\section{Side-by-Side Predictive Figures}",
        "The following figures place PyMC, CUQDyn FIM, and CUQDyn HybridCov panels side by side for each state. Within a given state row, all method panels use the same y-axis limits. Black markers are observations where available.",
    ])

    for label, relpath in figures:
        lines.extend([
            r"\begin{figure}[htbp]",
            r"\centering",
            rf"\includegraphics[width=0.96\linewidth]{{{relpath.as_posix()}}}",
            rf"\caption{{{tex_escape(label)} side-by-side CUQDyn1\_Plus versus PyMC predictive comparison.}}",
            r"\end{figure}",
            "",
        ])

    lines.extend([
        r"\clearpage",
        r"\begin{landscape}",
        r"\section{Full Parameter Table}",
    ])
    for model, rows in grouped(params, "Model").items():
        lines.append(rf"\subsection{{{tex_escape(model)}}}")
        rows_out = [
            [
                r["Method"],
                r["Parameter"],
                num(r["TrueValue"]),
                num(r["Estimate"]),
                num(r["StdDev"]),
                num(r["IntervalLower"]),
                num(r["IntervalUpper"]),
                pct(r["RelErrPercent"]),
            ]
            for r in rows
        ]
        lines.append(table(
            ["Method", "Parameter", "True", "Estimate", "StdDev", "Lower", "Upper", "RelErr %"],
            rows_out,
            r"p{0.24\linewidth}p{0.08\linewidth}rrrrrr",
            r"\scriptsize",
        ))

    lines.extend([
        r"\section{Full Trajectory-Band Table}",
    ])
    for model, rows in grouped(bands, "Model").items():
        lines.append(rf"\subsection{{{tex_escape(model)}}}")
        rows_out = [
            [
                r["Method"],
                r["State"],
                num(r["MeanBandWidth"]),
                num(r["MedianBandWidth"]),
                pct(r["ObservedCoveragePercent"]),
                num(r["RMSEObservedStates"]),
            ]
            for r in rows
        ]
        lines.append(table(
            ["Method", "State", "Mean band width", "Median band width", "Obs. coverage %", "Obs. RMSE"],
            rows_out,
            r"p{0.24\linewidth}p{0.12\linewidth}rrrr",
            r"\scriptsize",
        ))

    lines.extend([
        r"\end{landscape}",
        detailed_discussion(params, bands),
        r"\end{document}",
    ])

    tex_path = REPORT_DIR / "CUQDyn_vs_PyMC_comparison_report.tex"
    tex_path.write_text("\n".join(lines), encoding="utf-8")
    return tex_path


if __name__ == "__main__":
    path = make_report()
    print(path)
