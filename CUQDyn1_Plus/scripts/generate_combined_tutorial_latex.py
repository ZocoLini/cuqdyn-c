from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "EXAMPLES"
RUN_DATE = datetime.now().strftime("%Y-%m-%d")
REPORT_DIR = ROOT / "REPORTS" / f"CUQDyn1plus_combined_tutorial_{RUN_DATE}"
FIG_DIR = REPORT_DIR / "figures"


def latest_dir(base: Path, prefix: str) -> Path:
    matches = [p for p in base.iterdir() if p.is_dir() and p.name.startswith(prefix)]
    if not matches:
        raise FileNotFoundError(f"No directory starting with {prefix} in {base}")
    return max(matches, key=lambda p: p.stat().st_mtime)


def escape_latex(text: str) -> str:
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


def inline_markup(text: str) -> str:
    text = escape_latex(text)
    text = re.sub(r"`([^`]+)`", lambda m: r"\texttt{" + m.group(1) + "}", text)
    text = re.sub(r"\*\*([^*]+)\*\*", lambda m: r"\textbf{" + m.group(1) + "}", text)
    return text


def heading_command(level: int, base_level: int) -> str:
    effective = level + base_level - 1
    if effective <= 1:
        return "section"
    if effective == 2:
        return "subsection"
    if effective == 3:
        return "subsubsection"
    return "paragraph"


def markdown_table_to_latex(lines: list[str]) -> list[str]:
    rows = []
    for line in lines:
        parts = [p.strip() for p in line.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{3,}:?", p) for p in parts):
            continue
        rows.append(parts)
    if not rows:
        return []
    ncols = len(rows[0])
    align = "l" * ncols
    out = [r"\begin{center}", r"\small", r"\begin{tabular}{" + align + "}", r"\toprule"]
    out.append(" & ".join(inline_markup(c) for c in rows[0]) + r" \\")
    out.append(r"\midrule")
    for row in rows[1:]:
        row = row + [""] * (ncols - len(row))
        out.append(" & ".join(inline_markup(c) for c in row[:ncols]) + r" \\")
    out.extend([r"\bottomrule", r"\end{tabular}", r"\normalsize", r"\end{center}"])
    return out


def md_to_latex(md_text: str, base_level: int = 1) -> str:
    out: list[str] = []
    lines = md_text.splitlines()
    i = 0
    in_itemize = False
    in_enumerate = False
    paragraph: list[str] = []

    def flush_paragraph():
        nonlocal paragraph
        if paragraph:
            out.append(inline_markup(" ".join(p.strip() for p in paragraph)))
            out.append("")
            paragraph = []

    def close_lists():
        nonlocal in_itemize, in_enumerate
        if in_itemize:
            out.append(r"\end{itemize}")
            out.append("")
            in_itemize = False
        if in_enumerate:
            out.append(r"\end{enumerate}")
            out.append("")
            in_enumerate = False

    while i < len(lines):
        line = lines[i]

        if line.startswith("```"):
            flush_paragraph()
            close_lists()
            language = line.strip("`").strip()
            code_lines = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                code_lines.append(lines[i])
                i += 1
            if language and language.lower() in {"matlab", "python"}:
                listing_language = "Matlab" if language.lower() == "matlab" else "Python"
                out.append(r"\begin{lstlisting}[language=%s,basicstyle=\ttfamily\small]" % listing_language)
            else:
                out.append(r"\begin{lstlisting}[basicstyle=\ttfamily\small]")
            out.extend(code_lines)
            out.append(r"\end{lstlisting}")
            out.append("")
            i += 1
            continue

        if line.strip().startswith("|") and i + 1 < len(lines) and set(lines[i + 1].replace("|", "").strip()) <= {"-", ":", " "}:
            flush_paragraph()
            close_lists()
            table_lines = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                table_lines.append(lines[i])
                i += 1
            out.extend(markdown_table_to_latex(table_lines))
            out.append("")
            continue

        heading = re.match(r"^(#{1,6})\s+(.*)$", line)
        if heading:
            flush_paragraph()
            close_lists()
            level = len(heading.group(1))
            title = inline_markup(heading.group(2))
            out.append(r"\{}{{{}}}".format(heading_command(level, base_level), title))
            out.append("")
            i += 1
            continue

        bullet = re.match(r"^\s*-\s+(.*)$", line)
        if bullet:
            flush_paragraph()
            if in_enumerate:
                out.append(r"\end{enumerate}")
                in_enumerate = False
            if not in_itemize:
                out.append(r"\begin{itemize}")
                in_itemize = True
            out.append(r"\item " + inline_markup(bullet.group(1)))
            i += 1
            continue

        enum = re.match(r"^\s*\d+\.\s+(.*)$", line)
        if enum:
            flush_paragraph()
            if in_itemize:
                out.append(r"\end{itemize}")
                in_itemize = False
            if not in_enumerate:
                out.append(r"\begin{enumerate}")
                in_enumerate = True
            out.append(r"\item " + inline_markup(enum.group(1)))
            i += 1
            continue

        if not line.strip():
            flush_paragraph()
            close_lists()
            i += 1
            continue

        paragraph.append(line)
        i += 1

    flush_paragraph()
    close_lists()
    return "\n".join(out)


def copy_figure(src: Path, name: str) -> str:
    dst = FIG_DIR / name
    shutil.copy2(src, dst)
    stem = Path(name).stem
    for sibling_suffix in [".pdf", ".eps"]:
        sibling = src.with_suffix(sibling_suffix)
        if sibling.exists():
            shutil.copy2(sibling, FIG_DIR / f"{stem}{sibling_suffix}")
    return f"figures/{name}"


def figure_block(path: str, caption: str, label: str, width: str = "0.84\\linewidth") -> str:
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


def build_figures() -> list[tuple[str, str, str]]:
    lv_tutorial = latest_dir(EXAMPLES / "LV", "Tutorial_LV_three_UQ_methods_")
    lv_fim = latest_dir(EXAMPLES / "LV", "Results_LV2_CUQDyn1_Plus_")
    lv_hyb = latest_dir(EXAMPLES / "LV", "Results_LV2_HybridCov_")
    sir_fim = latest_dir(EXAMPLES / "SIR", "Results_SIR_CUQDyn1Plus_")
    sir_hyb = latest_dir(EXAMPLES / "SIR", "Results_SIR_HybridCov_")
    ap_fim = latest_dir(EXAMPLES / "AP", "Results_AP_partobs1_4_")
    ap_hyb = latest_dir(EXAMPLES / "AP", "Results_AP_HybridCov_partobs1_4_")
    lc3 = latest_dir(EXAMPLES / "LinearCascade", "Results_LinearCascade3_known_truth_")

    specs = [
        (lv_tutorial / "lv_predator_three_uq_methods.png", "lv_three_methods.png", "LV predator comparison across FIM, HybridCov, and bootstrap."),
        (lv_fim / "hybrid_uq_plot.png", "lv_fim_uq.png", "LV FIM example output."),
        (lv_hyb / "diag_marginal_stddev.png", "lv_hybrid_marginal_stddev.png", "LV HybridCov marginal parameter standard deviation diagnostic."),
        (sir_fim / "hybrid_uq_plot.png", "sir_fim_uq.png", "SIR FIM example output."),
        (sir_hyb / "diag_band_comparison_state3.png", "sir_hybrid_state3_band_comparison.png", "SIR HybridCov band comparison for the recovered state."),
        (ap_fim / "hybrid_uq_plot.png", "ap_fim_uq.png", "Alpha-pinene FIM example output."),
        (ap_hyb / "hybrid_uq_plot.png", "ap_hybrid_uq.png", "Alpha-pinene HybridCov example output."),
        (lc3 / "hybrid_uq_plot.png", "linearcascade3_uq.png", "LinearCascade3 known-truth diagnostic output."),
    ]
    return [(copy_figure(src, dst), caption, dst.rsplit(".", 1)[0]) for src, dst, caption in specs if src.exists()]


def main() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    FIG_DIR.mkdir(parents=True, exist_ok=True)

    problem_md = (ROOT / "docs" / "tutorialProblemDef.md").read_text(encoding="utf-8")
    uq_md = (ROOT / "docs" / "tutorialUQ.md").read_text(encoding="utf-8")
    figures = build_figures()

    tex: list[str] = [
        r"\documentclass[11pt]{article}",
        r"\usepackage[margin=1in]{geometry}",
        r"\usepackage{graphicx}",
        r"\usepackage{booktabs}",
        r"\usepackage{longtable}",
        r"\usepackage{hyperref}",
        r"\usepackage{caption}",
        r"\usepackage{xcolor}",
        r"\usepackage{listings}",
        r"\lstset{breaklines=true,columns=fullflexible,keepspaces=true,frame=single,backgroundcolor=\color{gray!5}}",
        r"\title{CUQDyn1\_Plus Combined Tutorial}",
        rf"\date{{Generated {datetime.now().strftime('%Y-%m-%d %H:%M')}}}",
        r"\begin{document}",
        r"\maketitle",
        r"\tableofcontents",
        r"\clearpage",
        r"\part{Problem Definition Workflow}",
        md_to_latex(problem_md, base_level=1),
        r"\clearpage",
        r"\part{Prediction-UQ Workflow}",
        md_to_latex(uq_md, base_level=1),
        r"\clearpage",
        r"\part{Representative Figures From Example Results}",
        "The figures below are copied from the latest relevant result folders available in the local repository at generation time. They make this tutorial report self-contained enough to inspect the main workflows without opening each result directory manually.",
        "",
    ]

    for path, caption, label in figures:
        tex.append(figure_block(path, caption, f"fig:{label}"))

    tex.extend([r"\end{document}", ""])
    out_path = REPORT_DIR / "CUQDyn1plus_combined_tutorial.tex"
    out_path.write_text("\n".join(tex), encoding="utf-8")
    print(REPORT_DIR)
    print(out_path)


if __name__ == "__main__":
    main()
