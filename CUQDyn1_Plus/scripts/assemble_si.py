#!/usr/bin/env python
"""Assemble a single Supplementary Information (SI) LaTeX document.

This post-processes the three auto-generated CUQDyn1_Plus reports into
body-only fragments, generates additional appendices from raw result files
that no single report currently surfaces (per-run settings, UQ identifiability
diagnostics, Bayesian ABC-SMC diagnostics, HybridCov diagnostic figures, and
per-model method notes), and emits one master `supplementary_information.tex`
with a shared preamble, a single table of contents, and continuous S-prefixed
figure/table/section numbering.

It is a pure post-processor: it reads existing report/result outputs and does
not re-run any MATLAB/PyMC computation. Re-running it after a fresh evaluation
reproduces the SI. Paths at the top select the run to assemble.
"""
from __future__ import annotations
import os
import re
import shutil
import datetime as _dt
import glob
import hashlib
import pandas as pd

# Repo root derived from this script's location (scripts/ -> repo root), so the
# assembler is portable and needs no absolute paths.
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
REPORTS = os.path.join(REPO, "REPORTS")
EX = os.path.join(REPO, "EXAMPLES")
PYMC = os.path.join(REPO, "pymc_matlab", "results")


def _latest(pattern):
    """Newest directory matching a glob (timestamped names sort lexically)."""
    hits = sorted(d for d in glob.glob(pattern) if os.path.isdir(d))
    return hits[-1] if hits else None


def _latest_with(pattern, must_contain):
    """Newest matching directory that contains a given file (used to tell the
    NF-kB FIM and HybridCov run folders apart, since their names are identical
    except for the results .mat they hold)."""
    hits = sorted(d for d in glob.glob(pattern) if os.path.isdir(d))
    for d in reversed(hits):
        if os.path.exists(os.path.join(d, must_contain)):
            return d
    return None


# The three generated reports (auto-discovered latest per prefix).
RESULTS_REP = _latest(os.path.join(REPORTS, "CUQDyn1plus_results_report_*"))
PYMC_REP    = _latest(os.path.join(REPORTS, "CUQDyn_vs_PyMC_comparison_*"))
TUT_REP     = _latest(os.path.join(REPORTS, "CUQDyn1plus_combined_tutorial_*"))
for _name, _p in [("results report", RESULTS_REP), ("pymc comparison", PYMC_REP),
                  ("combined tutorial", TUT_REP)]:
    if _p is None:
        raise SystemExit("Could not find a %s folder under REPORTS/; "
                         "run the reports stage first." % _name)

# Date stamp taken from the results-report folder suffix (falls back to today).
STAMP = os.path.basename(RESULTS_REP).split("_")[-1] or _dt.date.today().isoformat()
OUT = os.path.join(REPORTS, f"Supplementary_Information_{STAMP}")
FIGDIR = os.path.join(OUT, "figures")
SECDIR = os.path.join(OUT, "sections")

# Main per-model result folders (model, method label, latest folder).
RUN_FOLDERS = [
    ("LV",   "FIM",       _latest(os.path.join(EX, "LV",  "Results_LV2_CUQDyn1_Plus_*"))),
    ("LV",   "HybridCov", _latest(os.path.join(EX, "LV",  "Results_LV2_HybridCov_*"))),
    ("SIR",  "FIM",       _latest(os.path.join(EX, "SIR", "Results_SIR_CUQDyn1Plus_*"))),
    ("SIR",  "HybridCov", _latest(os.path.join(EX, "SIR", "Results_SIR_HybridCov_*"))),
    ("AP",   "FIM",       _latest(os.path.join(EX, "AP",  "Results_AP_partobs1_4_*"))),
    ("AP",   "HybridCov", _latest(os.path.join(EX, "AP",  "Results_AP_HybridCov_partobs1_4_*"))),
    ("NFKB", "FIM",       _latest_with(os.path.join(EX, "NFKB", "Results_NFKB_*"),
                                       "CUQDyn1_Plus_results.mat")),
    ("NFKB", "HybridCov", _latest_with(os.path.join(EX, "NFKB", "Results_NFKB_*"),
                                       "CUQDyn1_Plus_HybridCov_results.mat")),
]

# HybridCov diagnostic figures live in the HybridCov run folders (LV, SIR).
HYB_DIAG = [
    ("LV",  RUN_FOLDERS[1][2]),
    ("SIR", RUN_FOLDERS[3][2]),
]

METHOD_NOTES = [
    ("Lotka-Volterra (LV)",      os.path.join(EX, "LV", "METHOD_NOTES.md")),
    ("SIR",                      os.path.join(EX, "SIR", "METHOD_NOTES.md")),
    ("Alpha-pinene (AP)",        os.path.join(EX, "AP", "METHOD_NOTES.md")),
    ("NF-$\\kappa$B",            os.path.join(EX, "NFKB", "METHOD_NOTES.md")),
    ("LinearCascade",            os.path.join(EX, "LinearCascade", "METHOD_NOTES.md")),
]

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def esc(s) -> str:
    """Escape arbitrary text for LaTeX."""
    if s is None:
        return ""
    s = str(s)
    repl = {
        "\\": r"\textbackslash{}", "&": r"\&", "%": r"\%", "$": r"\$",
        "#": r"\#", "_": r"\_", "{": r"\{", "}": r"\}", "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    out = []
    for ch in s:
        out.append(repl.get(ch, ch))
    return "".join(out)


def fmt(v) -> str:
    """Format a numeric-ish cell compactly."""
    try:
        f = float(v)
        if f != f:  # NaN
            return "--"
        if f == 0:
            return "0"
        if abs(f) >= 1e4 or (abs(f) < 1e-3 and f != 0):
            return f"{f:.3e}"
        return f"{f:.4g}"
    except (ValueError, TypeError):
        return esc(v)


_HLEVELS = ["part", "section", "subsection", "subsubsection", "paragraph"]


def normalize_headings(t: str) -> str:
    """Shift a fragment's headings so its shallowest level becomes \\section,
    preserving relative nesting. No-op when the fragment already starts at
    \\section; +1 shift when it starts at \\part (e.g. the tutorial)."""
    present = [i for i, name in enumerate(_HLEVELS)
               if re.search(r"\\" + name + r"\b", t)]
    if not present:
        return t
    shift = 1 - min(present)          # map shallowest present level -> section
    if shift == 0:
        return t
    for i in range(len(_HLEVELS) - 1, -1, -1):
        newi = min(i + shift, len(_HLEVELS) - 1)
        t = re.sub(r"\\" + _HLEVELS[i] + r"(\*?\{)", "@@H%d@@\\1" % newi, t)
    for i in range(len(_HLEVELS)):
        t = t.replace("@@H%d@@" % i, "\\" + _HLEVELS[i])
    return t


def extract_body(tex_path: str, ns: str) -> str:
    """Read a standalone report .tex and return a body-only fragment:
    preamble/title/toc/document-env removed, headings demoted by one level,
    figure paths namespaced to figures/<ns>/."""
    with open(tex_path, "r", encoding="utf-8") as fh:
        t = fh.read()
    # keep only what is inside document
    m = re.search(r"\\begin\{document\}", t)
    if m:
        t = t[m.end():]
    t = re.sub(r"\\end\{document\}.*", "", t, flags=re.DOTALL)
    # strip title machinery
    t = re.sub(r"\\maketitle", "", t)
    t = re.sub(r"\\tableofcontents", "", t)
    # normalize heading depth so each fragment starts at \section
    t = normalize_headings(t)
    # namespace figure includes
    t = t.replace("{figures/", "{figures/%s/" % ns)
    # namespace labels/refs so identical labels across reports do not collide
    t = re.sub(r"(\\(?:label|ref|pageref|autoref|eqref)\{)", r"\g<1>%s:" % ns, t)
    # let figures float (pack pages) instead of rigid [H] placement, which
    # leaves large white gaps below single figures.
    t = re.sub(r"\\begin\{figure\}\[H\]", r"\\begin{figure}[htbp]", t)
    t = t.strip()
    # drop leading \clearpage/\newpage so the part heading is not left alone
    # on an otherwise-blank page (these are leftovers from the stripped TOC).
    t = re.sub(r"\A(?:\s*\\(?:clearpage|newpage)\b)+", "", t).strip()
    return t


def copy_figs(src_report: str, ns: str):
    src = os.path.join(src_report, "figures")
    dst = os.path.join(FIGDIR, ns)
    if os.path.isdir(src):
        shutil.copytree(src, dst, dirs_exist_ok=True)


def _md5(path):
    with open(path, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()


def collect_editable_figs():
    """Populate OUT/matlab_figures/<ns>/<name>.fig with the editable MATLAB
    source figure for each embedded SI figure. The report generators copy (not
    re-render) the PNGs from the result folders, so each SI figure PNG is
    byte-identical to a source-folder PNG that sits next to its .fig; we match
    on content hash and copy that .fig under the SI figure's name."""
    # index source PNGs that have a sibling .fig, by content hash
    src_dirs = [f for _, _, f in RUN_FOLDERS if f]
    src_dirs += glob.glob(os.path.join(EX, "LinearCascade", "Results_*"))
    src_dirs += glob.glob(os.path.join(EX, "*", "SBC_Results_*"))
    src_dirs += glob.glob(os.path.join(EX, "LV", "Tutorial_*"))
    cmp = _latest(os.path.join(REPO, "pymc_matlab", "results", "comparison", "*"))
    if cmp:
        src_dirs += [cmp] + glob.glob(os.path.join(cmp, "*"))
    src_dirs += [os.path.join(REPO, "scripts", "si_assets")]  # bespoke SI figures
    index = {}
    seen = set()
    for d in src_dirs:
        if not d or not os.path.isdir(d) or d in seen:
            continue
        seen.add(d)
        for png in glob.glob(os.path.join(d, "*.png")):
            figp = png[:-4] + ".fig"
            if os.path.exists(figp):
                index.setdefault(_md5(png), figp)
    outroot = os.path.join(OUT, "matlab_figures")
    n = miss = 0
    misses = []
    for si_png in glob.glob(os.path.join(FIGDIR, "**", "*.png"), recursive=True):
        rel = os.path.relpath(si_png, FIGDIR)          # ns/name.png
        figp = index.get(_md5(si_png))
        if figp:
            dst = os.path.join(outroot, rel[:-4] + ".fig")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy(figp, dst)
            n += 1
        else:
            miss += 1
            misses.append(rel)
    print("editable .fig collected: %d (%d without a matching source .fig)" % (n, miss))
    if misses:
        print("  no .fig for:", ", ".join(sorted(misses)))


def longtable(colspec, header, rows, caption, label) -> str:
    out = [r"\small", r"\begin{longtable}{%s}" % colspec,
           r"\caption{%s}\label{%s}\\" % (caption, label),
           r"\toprule", header + r" \\", r"\midrule", r"\endfirsthead",
           r"\toprule", header + r" \\", r"\midrule", r"\endhead"]
    for r in rows:
        out.append(" & ".join(r) + r" \\")
    out += [r"\bottomrule", r"\end{longtable}", r"\normalsize", ""]
    return "\n".join(out)


# ---------------------------------------------------------------------------
# gap appendices
# ---------------------------------------------------------------------------
def appendix_settings() -> str:
    parts = [r"\section{Optimizer, ODE, cost and FIM settings per run}",
             "Effective run options recorded in each result folder's "
             "\\texttt{run\\_options.xlsx}. FIM and HybridCov share the same "
             "shared fitting core, so their optimizer/ODE/cost settings match; "
             "they differ only in the unobserved-state covariance construction.\n"]
    by_model = {}
    for model, method, folder in RUN_FOLDERS:
        p = os.path.join(folder, "run_options.xlsx")
        try:
            df = pd.read_excel(p, sheet_name="Options")
            d = {str(k): v for k, v in zip(df["Option"], df["Value"])}
        except Exception as e:
            d = {"(error)": str(e)}
        by_model.setdefault(model, {})[method] = d
    for model, methods in by_model.items():
        keys = []
        for m in methods.values():
            for k in m:
                if k not in keys:
                    keys.append(k)
        rows = []
        for k in keys:
            fimv = methods.get("FIM", {}).get(k, "")
            hybv = methods.get("HybridCov", {}).get(k, "")
            rows.append([r"\texttt{%s}" % esc(k), esc(fimv), esc(hybv)])
        parts.append(longtable(
            "p{0.42\\linewidth} p{0.24\\linewidth} p{0.24\\linewidth}",
            "Option & FIM & HybridCov",
            rows, f"Effective run settings for the {esc(model)} runs.",
            f"tab:settings_{model.lower()}"))
    return "\n".join(parts)


def appendix_identifiability() -> str:
    parts = [r"\section{UQ identifiability diagnostics}",
             "Post-hoc diagnostics from \\texttt{diagnose\\_uq\\_quality} "
             "(\\texttt{uq\\_diagnostics.xlsx}), generated for every main run. "
             "cond$(\\mathrm{Cov}_p)$ is the parameter-covariance condition "
             "number; unreliable bands are hidden states whose delta-method "
             "variance projects strongly onto weak FIM directions.\n"]
    rows = []
    for model, method, folder in RUN_FOLDERS:
        p = os.path.join(folder, "uq_diagnostics.xlsx")
        try:
            summ = pd.read_excel(p, sheet_name="Summary").iloc[0]
            cond = summ.get("ConditionNumberCovP", float("nan"))
            mineig = summ.get("MinCovEigenvalue", float("nan"))
            maxeig = summ.get("MaxCovEigenvalue", float("nan"))
            nneg = summ.get("NNegativeCovEigenvalues", "")
            ntiny = summ.get("NTinyCovEigenvalues", "")
            nparam = summ.get("NParams", "")
            try:
                rel = pd.read_excel(p, sheet_name="FIMReliability")
                nunrel = int(rel["BandUnreliable"].astype(bool).sum())
                maxweak = fmt(rel["MaxWeakFraction"].max())
            except Exception:
                nunrel, maxweak = "--", "--"
            rows.append([esc(model), esc(method), fmt(nparam), fmt(cond),
                         fmt(mineig), fmt(maxeig), fmt(nneg), fmt(ntiny),
                         str(nunrel), maxweak])
        except Exception as e:
            rows.append([esc(model), esc(method), "--", "err: " + esc(str(e)[:20]),
                         "--", "--", "--", "--", "--", "--"])
    parts.append(longtable(
        "ll r r r r r r r r",
        r"Model & Method & $n_p$ & cond(Cov) & $\lambda_{\min}$ & "
        r"$\lambda_{\max}$ & \#neg & \#tiny & \#unrel & max weak",
        rows, "Parameter-covariance conditioning and weak-direction "
              "reliability across all main runs.", "tab:identifiability"))
    return "\n".join(parts)


def appendix_bayes() -> str:
    parts = [r"\section{Bayesian ABC-SMC diagnostics}",
             "Convergence and posterior summaries for the PyMC ABC-SMC "
             "reference. NF-$\\kappa$B exports full SMC diagnostics "
             "(\\texttt{smc\\_diagnostics.csv}: split-$\\hat R$ and effective "
             "sample sizes); LV/SIR/AP expose pooled posterior draws "
             "(\\texttt{posterior\\_samples.csv}) from which posterior mean, "
             "standard deviation, and central 95\\% intervals are computed.\n"]
    # NF-kB full SMC diagnostics
    try:
        sd = pd.read_csv(os.path.join(PYMC, "nfkb", "smc_diagnostics.csv"))
        rows = []
        for _, r in sd.iterrows():
            rows.append([esc(r.iloc[0]), fmt(r["mean"]), fmt(r["sd"]),
                         fmt(r["hdi_2.5%"]), fmt(r["hdi_97.5%"]),
                         fmt(r["ess_bulk"]), fmt(r["ess_tail"]), fmt(r["r_hat"])])
        parts.append(longtable(
            "l r r r r r r r",
            r"Param & mean & sd & 2.5\% & 97.5\% & ESS$_{\rm bulk}$ & "
            r"ESS$_{\rm tail}$ & $\hat R$",
            rows, "NF-$\\kappa$B ABC-SMC posterior and convergence diagnostics.",
            "tab:smc_nfkb"))
    except Exception as e:
        parts.append("NF-$\\kappa$B SMC diagnostics unavailable: %s\n" % esc(str(e)))
    # LV/SIR/AP posterior summaries
    for model in ("lv", "sir", "ap"):
        try:
            pp = pd.read_csv(os.path.join(PYMC, model, "posterior_samples.csv"))
            rows = []
            for c in pp.columns:
                s = pp[c]
                rows.append([esc(c), fmt(s.mean()), fmt(s.std()),
                             fmt(s.quantile(0.025)), fmt(s.quantile(0.975))])
            parts.append(longtable(
                "l r r r r",
                r"Parameter & mean & sd & 2.5\% & 97.5\%",
                rows, f"{model.upper()} ABC-SMC posterior summary "
                      f"({len(pp)} pooled draws).", f"tab:post_{model}"))
        except Exception as e:
            parts.append("%s posterior summary unavailable: %s\n" % (model.upper(), esc(str(e))))
    return "\n".join(parts)


def appendix_hybdiag() -> str:
    parts = [r"\section{HybridCov covariance diagnostics}",
             "HybridCov replaces the FIM parameter correlation with the LOO "
             "empirical correlation while keeping the FIM marginal scale. The "
             "figures below (produced for the low-dimensional LV and SIR runs) "
             "show the LOO correlation matrix, the FIM-vs-LOO marginal standard "
             "deviations, and the resulting hidden-state band comparison.\n"]
    dstroot = os.path.join(FIGDIR, "hybdiag")
    os.makedirs(dstroot, exist_ok=True)
    for model, folder in HYB_DIAG:
        pref = model.lower()
        figs = sorted(f for f in os.listdir(folder)
                      if f.startswith("diag_") and f.endswith(".png"))
        parts.append(r"\subsection{%s}" % esc(model))
        for f in figs:
            newname = f"{pref}_{f}"
            shutil.copy(os.path.join(folder, f), os.path.join(dstroot, newname))
            nice = f.replace("diag_", "").replace(".png", "").replace("_", " ")
            parts.append(r"\begin{figure}[H]\centering")
            parts.append(r"\includegraphics[width=0.8\linewidth]{figures/hybdiag/%s}" % newname)
            parts.append(r"\caption{%s HybridCov diagnostic: %s.}" % (esc(model), esc(nice)))
            parts.append(r"\end{figure}")
        parts.append("")
    return "\n".join(parts)


def md_to_latex(md: str) -> str:
    """Minimal, safe Markdown -> LaTeX for METHOD_NOTES files."""
    lines = md.splitlines()
    out = []
    in_list = False
    in_code = False
    for ln in lines:
        if ln.strip().startswith("```"):
            if in_code:
                out.append(r"\end{verbatim}")
                in_code = False
            else:
                if in_list:
                    out.append(r"\end{itemize}"); in_list = False
                out.append(r"\begin{verbatim}")
                in_code = True
            continue
        if in_code:
            out.append(ln)
            continue
        h = re.match(r"^(#{1,6})\s+(.*)$", ln)
        if h:
            if in_list:
                out.append(r"\end{itemize}"); in_list = False
            lvl = len(h.group(1))
            cmd = {1: "subsubsection"}.get(lvl, "paragraph")
            out.append("\\%s{%s}" % (cmd, inline_md(h.group(2))))
            continue
        li = re.match(r"^\s*[-*]\s+(.*)$", ln)
        if li:
            if not in_list:
                out.append(r"\begin{itemize}"); in_list = True
            out.append(r"\item " + inline_md(li.group(1)))
            continue
        if not ln.strip():
            if in_list:
                out.append(r"\end{itemize}"); in_list = False
            out.append("")
            continue
        out.append(inline_md(ln))
    if in_list:
        out.append(r"\end{itemize}")
    if in_code:
        out.append(r"\end{verbatim}")
    return "\n".join(out)


def inline_md(s: str) -> str:
    """Handle inline code/bold within a text line, escaping the rest."""
    # protect inline code
    tokens = re.split(r"(`[^`]*`|\*\*[^*]+\*\*)", s)
    out = []
    for tok in tokens:
        if tok.startswith("`") and tok.endswith("`") and len(tok) >= 2:
            out.append(r"\texttt{%s}" % esc(tok[1:-1]))
        elif tok.startswith("**") and tok.endswith("**") and len(tok) >= 4:
            out.append(r"\textbf{%s}" % esc(tok[2:-2]))
        else:
            out.append(esc(tok))
    return "".join(out)


def appendix_method_notes() -> str:
    parts = [r"\section{Per-model method notes}",
             "Reproduced from each example's \\texttt{METHOD\\_NOTES.md}: the "
             "rationale for observed-state choice, residual scaling, parameter "
             "bounds, and selected UQ workflows.\n"]
    for title, path in METHOD_NOTES:
        parts.append(r"\subsection{%s}" % title)
        try:
            with open(path, "r", encoding="utf-8") as fh:
                md = fh.read()
            # drop the file's leading H1 title (my subsection already names it)
            md = re.sub(r"\A\s*#\s+.*(?:\r?\n|$)", "", md, count=1)
            parts.append(md_to_latex(md))
        except Exception as e:
            parts.append("(method notes unavailable: %s)" % esc(str(e)))
        parts.append("")
    return "\n".join(parts)


def appendix_nonidentifiability() -> str:
    """A non-identifiability failure mode revealed by SBC on LinearCascade3, with
    the k1<->k2 illustration figure. Documents that the failure is invisible to
    the local FIM weak-direction diagnostic and is caught only by SBC."""
    src = os.path.join(REPO, "scripts", "si_assets", "lc3_k1k2_nonidentif.png")
    dst_dir = os.path.join(FIGDIR, "nonidentif")
    have_fig = os.path.exists(src)
    if have_fig:
        os.makedirs(dst_dir, exist_ok=True)
        shutil.copy(src, os.path.join(dst_dir, "lc3_k1k2_nonidentif.png"))
    parts = [
        r"\clearpage",  # flush any pending floats so the [H] figure below stays with its text
        r"\section{A non-identifiability failure mode revealed by SBC "
        r"(LinearCascade3)}",
        "LinearCascade3 observes only the terminal state $x_3$. Because $x_3(t)$ "
        "depends solely on the symmetric functions of the cascade poles "
        "$\\{k_1,k_2,k_3\\}$, the inverse problem has an exact "
        "$k_1\\!\\leftrightarrow\\!k_2$ permutation symmetry: the parameter sets "
        "$(k_1,k_2,k_3)$ and $(k_2,k_1,k_3)$ give numerically identical observed "
        "trajectories ($\\lVert x_3(k_1,k_2,k_3)-x_3(k_2,k_1,k_3)\\rVert\\approx "
        "10^{-9}$) but different hidden $x_1,x_2$. The parameter bounds pin $k_3$ "
        "as the slowest pole, leaving a clean two-fold degeneracy.\n",
    ]
    if have_fig:
        parts += [
            r"\begin{figure}[H]\centering",
            r"\includegraphics[width=\linewidth]{figures/nonidentif/lc3_k1k2_nonidentif.png}",
            r"\caption{LinearCascade3 upstream non-identifiability. A wrong-branch "
            r"fit (fitted parameters from a $0\%$-coverage SBC replicate) "
            r"reproduces the observed $x_3$ essentially exactly, yet gives very "
            r"different hidden $x_1$ and $x_2$ trajectories, so the delta-method "
            r"hidden-state bands are centered on the wrong trajectory.}",
            r"\label{fig:lc3_nonident}",
            r"\end{figure}",
            "",
        ]
    parts += [
        "This produces \\emph{bimodal} SBC coverage. Over 50 shared-fit "
        "replicates the optimizer recovers the correct branch on $\\sim$34 "
        "replicates ($\\approx$100\\% coverage) and the swapped branch on "
        "$\\sim$14 ($\\approx$0\\% coverage), giving a mean pointwise coverage of "
        "$\\approx$74\\% at the nominal 95\\% level (a smaller 20-replicate "
        "sample happens to draw mostly the correct branch and reports "
        "$\\approx$97\\%). On the failing replicates the wrong-branch parameters "
        "yield a \\emph{lower} objective than the true parameters, and a "
        "multistart initialized at the truth still converges to the wrong "
        "branch, so the failure cannot be removed by more optimizer effort.\n",
        "Notably, this failure is \\emph{not} flagged by the FIM weak-direction "
        "reliability diagnostic (Table~\\ref{tab:identifiability}): at either "
        "branch the local Gauss--Newton covariance is well conditioned "
        "($\\mathrm{cond}(\\mathrm{Cov}_\\theta)\\approx 10^{4}$, no weak "
        "directions), because the degeneracy is global and discrete rather than "
        "a local flat direction. Local identifiability diagnostics and SBC are "
        "therefore complementary: SBC is required to expose global or multimodal "
        "non-identifiability that leaves the local FIM well conditioned. FIM and "
        "HybridCov behave identically here, since the failure originates in the "
        "location of the fitted parameters, not in the covariance shape.\n",
    ]
    return "\n".join(parts)


def appendix_limitations() -> str:
    return "\n".join([
        r"\section{Coverage and scope limitations}",
        r"\begin{itemize}",
        r"\item Simulation-based calibration (SBC) was run for LV, SIR, AP and "
        r"LinearCascade3. It was \emph{not} run for NF-$\kappa$B (high state/"
        r"parameter dimension) or the 2-state LinearCascade; coverage claims "
        r"for those rest on the per-run diagnostics only.",
        r"\item Parametric bootstrap trajectory UQ is demonstrated only for the "
        r"LV tutorial; the other models use the FIM and HybridCov delta-method "
        r"bands.",
        r"\item HybridCov covariance-diagnostic figures are emitted only for the "
        r"low-dimensional LV and SIR runs.",
        r"\item Observed-state coverage is conformal (distribution-free under "
        r"exchangeability); unobserved-state coverage is approximate and local, "
        r"and should be read together with the identifiability diagnostics in "
        r"Table~\ref{tab:identifiability}.",
        r"\end{itemize}",
    ])


# ---------------------------------------------------------------------------
# master document
# ---------------------------------------------------------------------------
PREAMBLE = r"""\documentclass[11pt]{article}
\usepackage[margin=1in]{geometry}
\usepackage{graphicx}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{array}
\usepackage{float}
\usepackage{caption}
\usepackage{xcolor}
\usepackage{listings}
\usepackage{pdflscape}
\usepackage{tocloft}
\setlength{\cftsecnumwidth}{3em}
\setlength{\cftsubsecnumwidth}{3.4em}
% Make \part an in-flow heading (no dedicated near-blank part-title page).
\usepackage{titlesec}
\titleclass{\part}{straight}
\titleformat{\part}[block]{\normalfont\Large\bfseries}{Part~\thepart.}{0.6em}{}
\titlespacing*{\part}{0pt}{0.4\baselineskip}{1.0\baselineskip}
% Absorb minor line overflows instead of leaving overfull boxes.
\tolerance=1200
\setlength{\emergencystretch}{3em}
\usepackage[hidelinks]{hyperref}
\lstset{breaklines=true,columns=fullflexible,keepspaces=true,frame=single,
        basicstyle=\footnotesize\ttfamily,backgroundcolor=\color{gray!5}}
\setlength{\tabcolsep}{3pt}
\renewcommand{\arraystretch}{1.05}
% Continuous, S-prefixed supplementary numbering
\renewcommand{\thepart}{\Roman{part}}
\renewcommand{\thesection}{S\arabic{section}}
\renewcommand{\thesubsection}{\thesection.\arabic{subsection}}
\renewcommand{\thefigure}{S\arabic{figure}}
\renewcommand{\thetable}{S\arabic{table}}
\setcounter{tocdepth}{2}
\title{Supplementary Information\\[4pt]
\large CUQDyn1\_Plus: Hybrid Conformal--Gaussian Uncertainty Quantification
for Partially Observed Dynamical Systems}
\author{A.\ Portela \and J.\,R.\ Banga}
\date{Generated __DATE__}
"""

PREFACE = r"""\begin{document}
\maketitle
\begin{abstract}
\noindent This Supplementary Information consolidates the full computational
evaluation of the CUQDyn1\_Plus toolbox into a single document. It integrates
three automatically generated reports---the combined problem-definition and
three-method UQ tutorial, the empirical results across the maintained benchmark
models, and the CUQDyn1\_Plus-versus-PyMC ABC-SMC comparison---together with
additional appendices that document per-run settings, UQ identifiability
diagnostics, Bayesian convergence diagnostics, HybridCov covariance diagnostics,
an analytic LinearCascade3 non-identifiability case study, per-model method
notes, and scope limitations. All figures and tables use
supplementary (S-prefixed) numbering. Every artifact was produced by a single
end-to-end run (\texttt{scripts/run\_full\_evaluation.m}); Part~IV collects the
additional diagnostics and the exact per-run reproduction parameters.
\end{abstract}
\tableofcontents
\clearpage
"""


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(FIGDIR, exist_ok=True)
    os.makedirs(SECDIR, exist_ok=True)

    # 1) figures from the three reports
    copy_figs(RESULTS_REP, "results")
    copy_figs(PYMC_REP, "comparison")
    copy_figs(TUT_REP, "tutorial")

    # 2) body fragments
    frag_results = extract_body(os.path.join(RESULTS_REP, "CUQDyn1plus_results_report.tex"), "results")
    frag_pymc    = extract_body(os.path.join(PYMC_REP, "CUQDyn_vs_PyMC_comparison_report.tex"), "comparison")
    frag_tut     = extract_body(os.path.join(TUT_REP, "CUQDyn1plus_combined_tutorial.tex"), "tutorial")
    for name, frag in [("frag_results.tex", frag_results),
                       ("frag_pymc.tex", frag_pymc),
                       ("frag_tutorial.tex", frag_tut)]:
        with open(os.path.join(SECDIR, name), "w", encoding="utf-8") as fh:
            fh.write(frag)

    # 3) gap appendices
    appendices = {
        "app_settings.tex": appendix_settings(),
        "app_identifiability.tex": appendix_identifiability(),
        "app_bayes.tex": appendix_bayes(),
        "app_hybdiag.tex": appendix_hybdiag(),
        "app_nonidentif.tex": appendix_nonidentifiability(),
        "app_method_notes.tex": appendix_method_notes(),
        "app_limitations.tex": appendix_limitations(),
    }
    for name, body in appendices.items():
        with open(os.path.join(SECDIR, name), "w", encoding="utf-8") as fh:
            fh.write(body)

    # 4) master
    today = _dt.date.today().isoformat()
    master = [PREAMBLE.replace("__DATE__", today), PREFACE]
    master.append(r"\part{Problem definition and three-method UQ tutorial}")
    master.append(r"\input{sections/frag_tutorial.tex}")
    master.append(r"\clearpage")
    master.append(r"\part{Empirical results across benchmark models}")
    master.append(r"\input{sections/frag_results.tex}")
    master.append(r"\clearpage")
    master.append(r"\part{CUQDyn1\_Plus versus PyMC ABC-SMC}")
    master.append(r"\input{sections/frag_pymc.tex}")
    master.append(r"\clearpage")
    master.append(r"\part{Additional diagnostics and reproducibility}")
    master.append(r"\input{sections/app_identifiability.tex}")
    master.append(r"\input{sections/app_hybdiag.tex}")
    master.append(r"\input{sections/app_nonidentif.tex}")
    master.append(r"\input{sections/app_bayes.tex}")
    master.append(r"\input{sections/app_settings.tex}")
    master.append(r"\input{sections/app_method_notes.tex}")
    master.append(r"\input{sections/app_limitations.tex}")
    master.append(r"\end{document}")

    with open(os.path.join(OUT, "supplementary_information.tex"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(master))
    print("SI written to", OUT)

    # editable MATLAB source figures alongside the SI
    collect_editable_figs()


if __name__ == "__main__":
    main()
