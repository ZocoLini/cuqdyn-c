from __future__ import annotations

import math
import re
import shutil
from datetime import datetime
from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "EXAMPLES"
RUN_DATE = datetime.now().strftime("%Y-%m-%d")
REPORT_DIR = ROOT / "REPORTS" / f"CUQDyn1plus_results_report_{RUN_DATE}"
FIG_DIR = REPORT_DIR / "figures"


def escape_latex(value) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and math.isnan(value):
        return "--"
    text = str(value)
    replacements = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    return text


def fmt(value, digits=3) -> str:
    if value is None:
        return "--"
    try:
        if pd.isna(value):
            return "--"
    except TypeError:
        pass
    if isinstance(value, (int, float)):
        value = float(value)
        if value == 0:
            return "0"
        if abs(value) >= 1000 or abs(value) < 1e-3:
            return f"{value:.{digits}e}"
        return f"{value:.{digits}f}".rstrip("0").rstrip(".")
    return escape_latex(value)


def latest_dir(base: Path, prefix: str) -> Path:
    matches = [p for p in base.iterdir() if p.is_dir() and p.name.startswith(prefix)]
    if not matches:
        raise FileNotFoundError(f"No directory starting with {prefix} in {base}")
    return max(matches, key=lambda p: p.stat().st_mtime)


def latest_dir_with_file(base: Path, prefix: str, filename: str) -> Path:
    matches = [
        p for p in base.iterdir()
        if p.is_dir() and p.name.startswith(prefix) and (p / filename).exists()
    ]
    if not matches:
        raise FileNotFoundError(f"No directory starting with {prefix} and containing {filename} in {base}")
    return max(matches, key=lambda p: p.stat().st_mtime)


def copy_figure(src: Path, label: str) -> str:
    if not src.exists():
        return ""
    suffix = src.suffix.lower()
    dst = FIG_DIR / f"{label}{suffix}"
    shutil.copy2(src, dst)
    for sibling_suffix in [".pdf", ".eps"]:
        sibling = src.with_suffix(sibling_suffix)
        if sibling.exists():
            shutil.copy2(sibling, FIG_DIR / f"{label}{sibling_suffix}")
    return f"figures/{dst.name}"


def latex_table(headers, rows, caption: str, label: str, align: str | None = None) -> str:
    if align is None:
        align = "l" * len(headers)
    out = [
        r"\begin{table}[htbp]",
        r"\centering",
        r"\small",
        r"\begin{tabular}{" + align + "}",
        r"\toprule",
        " & ".join(headers) + r" \\",
        r"\midrule",
    ]
    for row in rows:
        out.append(" & ".join(fmt(v) for v in row) + r" \\")
    out.extend(
        [
            r"\bottomrule",
            r"\end{tabular}",
            rf"\caption{{{escape_latex(caption)}}}",
            rf"\label{{{label}}}",
            r"\end{table}",
            "",
        ]
    )
    return "\n".join(out)


def latex_longtable(headers, rows, caption: str, label: str, align: str | None = None) -> str:
    if align is None:
        align = "l" * len(headers)
    out = [
        r"\small",
        r"\begin{longtable}{" + align + "}",
        rf"\caption{{{escape_latex(caption)}}}\label{{{label}}}\\",
        r"\toprule",
        " & ".join(headers) + r" \\",
        r"\midrule",
        r"\endfirsthead",
        r"\toprule",
        " & ".join(headers) + r" \\",
        r"\midrule",
        r"\endhead",
    ]
    for row in rows:
        out.append(" & ".join(fmt(v) for v in row) + r" \\")
    out.extend([r"\bottomrule", r"\end{longtable}", r"\normalsize", ""])
    return "\n".join(out)


def figure_block(path: str, caption: str, label: str, width="0.84\\linewidth") -> str:
    if not path:
        return ""
    return "\n".join(
        [
            r"\begin{figure}[htbp]",
            r"\centering",
            rf"\includegraphics[width={width}]{{{path}}}",
            rf"\caption{{{escape_latex(caption)}}}",
            rf"\label{{{label}}}",
            r"\end{figure}",
            "",
        ]
    )


def read_excel_table(path: Path, sheet: str) -> pd.DataFrame:
    if not path.exists():
        return pd.DataFrame()
    return pd.read_excel(path, sheet_name=sheet)


def trajectory_summary_rows(example: str, method: str, folder: Path):
    path = folder / "trajectory_nrmse_tables.xlsx"
    if not path.exists():
        return []
    df = read_excel_table(path, "UQSummary")
    rows = []
    for _, r in df.iterrows():
        rows.append(
            [
                example,
                method,
                r.get("StateName"),
                r.get("CoveragePercent"),
                r.get("MeanIntervalWidth"),
                r.get("NormalizedMeanIntervalWidth"),
            ]
        )
    return rows


def error_summary_rows(example: str, method: str, folder: Path):
    path = folder / "trajectory_nrmse_tables.xlsx"
    if not path.exists():
        return []
    df = read_excel_table(path, "ErrorSummary")
    rows = []
    for _, r in df.iterrows():
        rows.append(
            [
                example,
                method,
                r.get("StateName"),
                r.get("RMSE"),
                r.get("MAE"),
                r.get("NRMSEPercent"),
            ]
        )
    return rows


def linear_reference_row(example: str, folder: Path, workbook: str):
    path = folder / workbook
    df = read_excel_table(path, "Summary")
    if df.empty:
        return []
    r = df.iloc[0]
    return [
        example,
        r.get("CovRelFroError"),
        r.get("HiddenStdRelError"),
        r.get("MaxTrajectoryReferenceError", r.get("MaxTrajectoryAnalyticError")),
    ]


def parse_ap_sbc(log_path: Path):
    text = log_path.read_text(errors="replace")
    rows = []
    for method in ["FIM", "HYB"]:
        block_match = re.search(rf"--- {method} ---\n(?P<block>.*?)(?=\n---|\nLOO|\Z)", text, re.S)
        if not block_match:
            continue
        block = block_match.group("block")
        rows.append(
            [
                "AP",
                "HybridCov" if method == "HYB" else "FIM",
                "State 5",
                regex_float(block, r"Mean pointwise coverage .*?:\s*([0-9.]+)%"),
                regex_float(block, r"Std\s+pointwise coverage:\s*([0-9.]+)%"),
                regex_float(block, r"Simultaneous coverage:\s*([0-9.]+)%"),
                regex_float(block, r"Mean band width .*?:\s*([0-9.eE+-]+)"),
            ]
        )
    return rows


def parse_sir_sbc(log_path: Path):
    text = log_path.read_text(errors="replace")
    rows = []
    for method in ["FIM", "HYB"]:
        block_match = re.search(rf"--- {method} ---\n(?P<block>.*?)(?=\n---|\nLOO|\Z)", text, re.S)
        if not block_match:
            continue
        block = block_match.group("block")
        state_blocks = re.finditer(r"State\s+\d+\s+\((?P<state>[^)]+)\):(?P<body>.*?)(?=\n\s*State|\Z)", block, re.S)
        for m in state_blocks:
            body = m.group("body")
            rows.append(
                [
                    "SIR",
                    "HybridCov" if method == "HYB" else "FIM",
                    m.group("state"),
                    regex_float(body, r"Mean ptwise coverage\s*:\s*([0-9.]+)%"),
                    regex_float(body, r"Std\s+ptwise coverage\s*:\s*([0-9.]+)%"),
                    regex_float(body, r"Simultaneous coverage:\s*([0-9.]+)%"),
                    regex_float(body, r"Mean band width\s*:\s*([0-9.eE+-]+)"),
                ]
            )
    return rows


def parse_lv_sbc(log_path: Path):
    text = log_path.read_text(errors="replace")
    coverage = re.findall(r"coverage FIM=([0-9.]+)%\s+HYB=([0-9.]+)%", text)
    widths = re.findall(r"width\s+FIM=([0-9.]+)\s+HYB=([0-9.]+)", text)
    rows = []
    for idx, method in enumerate(["FIM", "HybridCov"]):
        cov = [float(c[idx]) for c in coverage]
        wid = [float(w[idx]) for w in widths]
        if cov:
            mean = sum(cov) / len(cov)
            std = (sum((x - mean) ** 2 for x in cov) / max(len(cov) - 1, 1)) ** 0.5
            sim = 100 * sum(x >= 100 for x in cov) / len(cov)
            rows.append(["LV", method, "Predator", mean, std, sim, sum(wid) / len(wid)])
    return rows


def regex_float(text: str, pattern: str):
    m = re.search(pattern, text)
    return float(m.group(1)) if m else None


def main():
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    FIG_DIR.mkdir(parents=True, exist_ok=True)

    folders = {
        "LV FIM": latest_dir(EXAMPLES / "LV", "Results_LV2_CUQDyn1_Plus_"),
        "LV HybridCov": latest_dir(EXAMPLES / "LV", "Results_LV2_HybridCov_"),
        "LV tutorial": latest_dir(EXAMPLES / "LV", "Tutorial_LV_three_UQ_methods_"),
        "LV SBC": latest_dir(EXAMPLES / "LV", "SBC_Results_LV2_FIM_vs_HybridCov_sharedfit_"),
        "SIR FIM": latest_dir(EXAMPLES / "SIR", "Results_SIR_CUQDyn1Plus_"),
        "SIR HybridCov": latest_dir(EXAMPLES / "SIR", "Results_SIR_HybridCov_"),
        "SIR SBC": latest_dir(EXAMPLES / "SIR", "SBC_Results_SIR_FIM_vs_HybridCov_"),
        "AP FIM": latest_dir(EXAMPLES / "AP", "Results_AP_partobs1_4_"),
        "AP HybridCov": latest_dir(EXAMPLES / "AP", "Results_AP_HybridCov_partobs1_4_"),
        "AP SBC": latest_dir(EXAMPLES / "AP", "SBC_Results_AP_FIM_vs_HybridCov_"),
        "NFKB FIM": latest_dir_with_file(EXAMPLES / "NFKB", "Results_NFKB_", "CUQDyn1_Plus_results.mat"),
        "NFKB HybridCov": latest_dir_with_file(EXAMPLES / "NFKB", "Results_NFKB_", "CUQDyn1_Plus_HybridCov_results.mat"),
        "LinearCascade": latest_dir(EXAMPLES / "LinearCascade", "Results_LinearCascade_known_truth_"),
        "LinearCascade3": latest_dir(EXAMPLES / "LinearCascade", "Results_LinearCascade3_known_truth_"),
        "LinearCascade3 SBC": latest_dir(EXAMPLES / "LinearCascade", "SBC_Results_LinearCascade3_sharedfit_"),
    }

    source_rows = [[k, v.relative_to(ROOT).as_posix()] for k, v in folders.items()]

    uq_rows = []
    err_rows = []
    for ex, method, key in [
        ("LV", "FIM", "LV FIM"),
        ("LV", "HybridCov", "LV HybridCov"),
        ("SIR", "FIM", "SIR FIM"),
        ("SIR", "HybridCov", "SIR HybridCov"),
        ("AP", "FIM", "AP FIM"),
        ("AP", "HybridCov", "AP HybridCov"),
        ("LinearCascade", "FIM", "LinearCascade"),
        ("LinearCascade3", "FIM", "LinearCascade3"),
    ]:
        uq_rows.extend(trajectory_summary_rows(ex, method, folders[key]))
        err_rows.extend(error_summary_rows(ex, method, folders[key]))

    lv_tutorial_path = folders["LV tutorial"] / "three_uq_methods_metric_comparison.xlsx"
    lv_latent = read_excel_table(lv_tutorial_path, "LatentTruthCoverage")
    lv_latent_rows = [
        [r.Method, r.State, r.LatentCoveragePercent, r.MeanIntervalWidth, r.NormalizedMeanIntervalWidth]
        for _, r in lv_latent.iterrows()
    ]

    linear_rows = [
        linear_reference_row(
            "LinearCascade",
            folders["LinearCascade"],
            "linear_cascade_numerics_summary.xlsx",
        ),
        linear_reference_row(
            "LinearCascade3",
            folders["LinearCascade3"],
            "linear_cascade3_numerics_summary.xlsx",
        ),
    ]

    sbc_rows = []
    sbc_rows.extend(parse_lv_sbc(folders["LV SBC"] / "sbc_log.txt"))
    sbc_rows.extend(parse_sir_sbc(folders["SIR SBC"] / "sbc_log.txt"))
    sbc_rows.extend(parse_ap_sbc(folders["AP SBC"] / "sbc_log.txt"))
    lc3_sbc = read_excel_table(folders["LinearCascade3 SBC"] / "linear_cascade3_sbc_summary.xlsx", "Summary")
    for _, r in lc3_sbc.iterrows():
        sbc_rows.append(
            [
                "LinearCascade3",
                r.Method,
                r.State,
                r.MeanPointwiseCoveragePercent,
                r.StdPointwiseCoveragePercent,
                r.SimultaneousCoveragePercent,
                r.MeanBandWidth,
            ]
        )

    # Per-example nominal coverage level so the mixed-example SBC table is
    # unambiguous (alp: LV / LinearCascade3 = 0.025 -> 95%; SIR / AP = 0.05 -> 90%).
    _sbc_nominal = {"LV": 95, "SIR": 90, "AP": 90, "LinearCascade3": 95}
    sbc_rows = [list(r[:3]) + [_sbc_nominal.get(r[0], "")] + list(r[3:]) for r in sbc_rows]

    fig_specs = [
        ("lv_fim_uq", folders["LV FIM"] / "hybrid_uq_plot.png", "LV FIM fit and UQ bands."),
        ("lv_hyb_uq", folders["LV HybridCov"] / "hybrid_uq_plot.png", "LV HybridCov fit and UQ bands."),
        ("lv_three_methods", folders["LV tutorial"] / "lv_predator_three_uq_methods.png", "LV predator comparison across FIM, HybridCov, and bootstrap."),
        ("sir_fim_uq", folders["SIR FIM"] / "hybrid_uq_plot.png", "SIR FIM fit and UQ bands."),
        ("sir_hyb_diag", folders["SIR HybridCov"] / "diag_band_comparison_state3.png", "SIR HybridCov diagnostic band comparison for recovered state."),
        ("ap_fim_uq", folders["AP FIM"] / "hybrid_uq_plot.png", "AP FIM fit and UQ bands after widened bounds."),
        ("ap_hyb_uq", folders["AP HybridCov"] / "hybrid_uq_plot.png", "AP HybridCov fit and UQ bands after widened bounds."),
        ("nfkb_fim_uq", folders["NFKB FIM"] / "hybrid_uq_plot.png", "NF-kB FIM fit and UQ bands after widened bounds."),
        ("nfkb_hyb_uq", folders["NFKB HybridCov"] / "hybrid_uq_plot.png", "NF-kB HybridCov fit and UQ bands after widened bounds."),
        ("lc_uq", folders["LinearCascade"] / "hybrid_uq_plot.png", "Two-state LinearCascade known-truth diagnostic."),
        ("lc3_uq", folders["LinearCascade3"] / "hybrid_uq_plot.png", "Three-state LinearCascade3 known-truth diagnostic."),
        ("sbc_lv_cov", folders["LV SBC"] / "fig1_coverage_by_time.png", "LV shared-fit SBC coverage by time."),
        ("sbc_lv_summary", folders["LV SBC"] / "fig5_summary.png", "LV shared-fit SBC summary."),
        ("sbc_sir_summary", folders["SIR SBC"] / "fig7_summary.png", "SIR SBC summary."),
        ("sbc_ap_summary", folders["AP SBC"] / "fig7_summary.png", "AP SBC summary."),
        ("sbc_lc3_cov", folders["LinearCascade3 SBC"] / "fig1_hidden_coverage_by_time.png", "LinearCascade3 shared-fit SBC hidden-state coverage by time."),
        ("sbc_lc3_width", folders["LinearCascade3 SBC"] / "fig2_hidden_band_widths.png", "LinearCascade3 shared-fit SBC hidden-state band widths."),
    ]

    figures = [(label, copy_figure(src, label), caption) for label, src, caption in fig_specs]

    tex = []
    tex.extend(
        [
            r"\documentclass[11pt]{article}",
            r"\usepackage[margin=1in]{geometry}",
            r"\usepackage{graphicx}",
            r"\usepackage{booktabs}",
            r"\usepackage{longtable}",
            r"\usepackage{float}",
            r"\usepackage{hyperref}",
            r"\usepackage{caption}",
            r"\usepackage{array}",
            r"\title{CUQDyn1\_Plus Results Report}",
            rf"\date{{Generated {datetime.now().strftime('%Y-%m-%d %H:%M')}}}",
            r"\begin{document}",
            r"\maketitle",
            "",
            r"\section{Scope}",
            "This report was generated automatically from the latest available result folders in the local CUQDyn1\\_Plus repository. "
            "It includes the maintained non-SBC examples, the latest LV three-method tutorial output, and the latest available SBC calibration folders. "
            f"AP and NF-kB results use the latest folders available on {RUN_DATE}.",
            "",
        ]
    )

    tex.append(latex_longtable(["Label", "Source folder"], source_rows, "Result folders used in this report.", "tab:sources", "p{0.23\\linewidth}p{0.68\\linewidth}"))

    tex.extend([r"\section{Trajectory Fit and Prediction-UQ Summaries}", ""])
    tex.append(latex_longtable(
        ["Example", "Method", "State", "Coverage (\\%)", "Mean width", "Norm. width"],
        uq_rows,
        "Trajectory uncertainty summaries from trajectory_nrmse_tables.xlsx where available.",
        "tab:uqsummary",
        "ll l r r r",
    ))
    tex.append(latex_longtable(
        ["Example", "Method", "State", "RMSE", "MAE", "NRMSE (\\%)"],
        err_rows,
        "Trajectory error summaries from trajectory_nrmse_tables.xlsx where available.",
        "tab:errorsummary",
        "ll l r r r",
    ))

    tex.extend([r"\section{LV Three-Method Tutorial}", ""])
    tex.append(latex_table(
        ["Method", "State", "Latent coverage (\\%)", "Mean width", "Norm. width"],
        lv_latent_rows,
        "Latent true-trajectory coverage from the LV three-method tutorial.",
        "tab:lvthree",
        "llrrr",
    ))
    for label, path, caption in figures[:3]:
        tex.append(figure_block(path, caption, f"fig:{label}"))

    tex.extend([r"\section{Linear Cascade Known-Truth Checks}", ""])
    tex.append(latex_table(
        ["Example", "Cov. rel. Fro. error", "Hidden std rel. error", "Max traj. ref. error"],
        linear_rows,
        "Known-truth numerical reference checks for LinearCascade examples.",
        "tab:linearref",
        "lrrr",
    ))
    for label, path, caption in figures[9:11]:
        tex.append(figure_block(path, caption, f"fig:{label}"))

    tex.extend([r"\section{Simulation-Based Calibration}", ""])
    tex.append(
        "SBC tables report hidden-state or unobserved-state coverage from the latest available calibration folders. "
        "Nominal coverage differs by script: the SIR and AP logs report 90\\% nominal intervals, while the LinearCascade3 shared-fit run reports 95\\% nominal intervals."
    )
    tex.append(latex_longtable(
        ["Example", "Method", "State", "Nominal (\\%)", "Mean ptwise cov. (\\%)", "Std ptwise cov. (\\%)", "Simult. cov. (\\%)", "Mean width"],
        sbc_rows,
        "SBC coverage and band-width summaries. The nominal column gives each "
        "example's target two-sided level (LV and LinearCascade3 at 95\\%; SIR "
        "and AP at 90\\%), since coverage should be read against it.",
        "tab:sbc",
        "lllrrrrr",
    ))
    for label, path, caption in figures[11:]:
        tex.append(figure_block(path, caption, f"fig:{label}", width="0.78\\linewidth"))

    tex.extend([r"\section{Example Figures}", ""])
    for label, path, caption in figures[3:9]:
        tex.append(figure_block(path, caption, f"fig:{label}"))

    tex.extend(
        [
            r"\section{Notes and Caveats}",
            r"\begin{itemize}",
            r"\item Tables are extracted from generated Excel workbooks and SBC logs; no examples were rerun by this report script.",
            r"\item NF-kB result workbooks do not currently include trajectory\_nrmse\_tables.xlsx, so NF-kB contributes figures and result folders but not a compact trajectory summary table.",
            r"\item Bootstrap intervals in the LV tutorial are latent trajectory intervals, not noisy-observation prediction intervals.",
            r"\item The LV shared-fit SBC folder contains figures and a log, but no xlsx summary; its SBC row is computed from per-replicate coverage and width lines in the log.",
            r"\end{itemize}",
            r"\end{document}",
        ]
    )

    (REPORT_DIR / "CUQDyn1plus_results_report.tex").write_text("\n".join(tex), encoding="utf-8")
    print(REPORT_DIR)
    print(REPORT_DIR / "CUQDyn1plus_results_report.tex")


if __name__ == "__main__":
    main()
