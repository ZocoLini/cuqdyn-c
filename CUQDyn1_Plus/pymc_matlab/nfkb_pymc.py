import os
import platform

if platform.system() == "Windows":
    os.environ["PYTENSOR_FLAGS"] = f"compiledir={os.path.abspath('.pytensor_cache')},cxx="

import arviz as az
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pymc as pm
from pathlib import Path
from scipy.integrate import odeint
from pymc_export_utils import RNG_SEED, N_TRAJ_EXPORT, noise_augmented_trajectories, numeric_summary_value, posterior_chain_draw_sizes, posterior_indices, stacked_posterior

# ── Data ──────────────────────────────────────────────────────────────────────
data = np.loadtxt(
    "../EXAMPLES/NFKB/data/NFKB_synthetic_data_5n_36st_partobs10.csv",
    delimiter=",", skiprows=1
)
t  = data[:, 0]
y0 = data[0, 1:]   # initial conditions for all 15 states (from t=0 row)

# Observed state indices (0-based within the state array):
# y1,y2,y3,y5,y7,y9,y11,y12,y13,y15  →  Python 0-based: 0,1,2,4,6,8,10,11,12,14
OBS_IDX   = np.array([0, 1, 2, 4, 6, 8, 10, 11, 12, 14])
OBS_NAMES = ["y1", "y2", "y3", "y5", "y7", "y9", "y11", "y12", "y13", "y15"]
N_STATES  = 15
N_OBS     = len(OBS_IDX)
N_TIMES   = len(t)

obs_matrix = data[:, 1:][:, OBS_IDX]   # (N_TIMES, N_OBS)
observed   = obs_matrix.reshape(-1)     # 1-D vector for PyMC Simulator

# Normalisation constants: each observed state is scaled by its trajectory maximum.
_scale = np.array([float(np.max(np.abs(obs_matrix[:, j]))) for j in range(N_OBS)])
_scale[_scale == 0] = 1.0
_obs_norm = obs_matrix / _scale   # (N_TIMES, N_OBS), values ~ O(1)

# ── True (nominal) parameters ─────────────────────────────────────────────────
# Matches true_parameters in run_NFKB_example.m
TRUE_PARAMS = np.array([
    0.5,    0.2,      0.1,      1.0,    0.1,
    5e-7,   0.0001,   0.0004,   0.5,    0.0001,
    0.00002,5e-7,     0.0001,   0.0004, 0.5,
    0.0003, 0.0025,   0.1,      0.0015, 0.000025,
    0.000125, 5.0,    0.0025,   0.01,   0.001,
    0.0005, 5e-7,     0.0001,   0.0004
])
N_PARAMS    = len(TRUE_PARAMS)   # 29
PARAM_NAMES = [f"p{i+1}" for i in range(N_PARAMS)]
NFKB_DRAWS = int(os.environ.get("NFKB_PYMC_DRAWS", "1000"))
RESULTS_DIR = Path(os.environ.get("NFKB_PYMC_RESULTS_DIR", "results/nfkb"))

# ── NF-κB ODE (15-state model) ────────────────────────────────────────────────
# Transcribed from prob_mod_dynamics_NFKB.m (MATLAB 1-based → Python 0-based)
def nfkb_ode(y, t, p):
    dy = np.zeros(15)
    dy[0]  = p[19] - p[20]*y[0] - p[16]*y[0]
    dy[1]  = (p[16]*y[0] - p[18]*y[1] - p[17]*y[1]*y[7] - p[20]*y[1]
              - p[1]*y[1]*y[9] + p[2]*y[3] - p[3]*y[1]*y[12] + p[4]*y[4])
    dy[2]  = p[18]*y[1] + p[17]*y[1]*y[7] - p[20]*y[2]
    dy[3]  = p[1]*y[1]*y[9] - p[2]*y[3]
    dy[4]  = p[3]*y[1]*y[12] - p[4]*y[4]
    dy[5]  = p[10]*y[12] - p[0]*y[5]*y[9] + p[4]*y[4] - p[22]*y[5]
    dy[6]  = p[22]*p[21]*y[5] - p[0]*y[10]*y[6]
    dy[7]  = p[14]*y[8] - p[15]*y[7]
    dy[8]  = p[12] + p[11]*y[6] - p[13]*y[8]
    dy[9]  = (-p[1]*y[1]*y[9] - p[0]*y[9]*y[5]
               + p[8]*y[11] - p[9]*y[9] - p[24]*y[9] + p[25]*y[10])
    dy[10] = -p[0]*y[10]*y[6] + p[24]*p[21]*y[9] - p[25]*p[21]*y[10]
    dy[11] = p[6] + p[5]*y[6] - p[7]*y[11]
    dy[12] = p[0]*y[9]*y[5] - p[10]*y[12] - p[3]*y[1]*y[12] + p[23]*y[13]
    dy[13] = p[0]*y[10]*y[6] - p[23]*p[21]*y[13]
    dy[14] = p[27] + p[26]*y[6] - p[28]*y[14]
    return dy


# ── Simulator ─────────────────────────────────────────────────────────────────
def nfkb_simulator(rng, p, size=None):
    p_arr = np.asarray(p, dtype=float).ravel()
    try:
        sol = odeint(nfkb_ode, y0=y0, t=t, rtol=1e-5, atol=1e-7,
                     args=(p_arr,), full_output=False)
        if not np.isfinite(sol).all():
            return np.full(N_TIMES * N_OBS, 1e6)
    except Exception:
        return np.full(N_TIMES * N_OBS, 1e6)
    return sol[:, OBS_IDX].reshape(-1)


# ── Normalised L1 distance ────────────────────────────────────────────────────
# Returns log-weight via a Laplace kernel: -distance / epsilon
# Each state is divided by its observed maximum so all states contribute equally.
def norm_l1_distance(epsilon, obs_data, sim_data):
    sim_2d = sim_data.reshape(N_TIMES, N_OBS)
    dist   = np.sum(np.abs(_obs_norm - sim_2d / _scale))
    return -dist / epsilon


# ── Inference ─────────────────────────────────────────────────────────────────
def run_sampling() -> az.InferenceData:
    with pm.Model():
        # Broad prior over the same positive parameter support used by CUQDyn.
        p = pm.Uniform("p",
                       lower=0.1 * TRUE_PARAMS,
                       upper=4.0 * TRUE_PARAMS,
                       shape=N_PARAMS)
        pm.Simulator(
            "sim",
            nfkb_simulator,
            params=(p,),
            distance=norm_l1_distance,
            epsilon=1.0,    # same scale as LV/AP examples; SMC reduces beta from 0→1
            observed=observed,
        )
        idata = pm.sample_smc(draws=NFKB_DRAWS, chains=4,
                              random_seed=RNG_SEED,
                              threshold=0.3, correlation_threshold=0.1)
    return idata


# ── CSV export ────────────────────────────────────────────────────────────────
def export_results(idata: az.InferenceData) -> np.ndarray:
    out_dir = RESULTS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    posterior = stacked_posterior(idata)
    post_p    = posterior["p"].values   # (N_PARAMS, n_samples)
    n_samples = post_p.shape[1]
    mean_p    = post_p.mean(axis=1)

    # posterior_samples.csv  — one column per parameter
    pd.DataFrame(post_p.T, columns=PARAM_NAMES).to_csv(
        out_dir / "posterior_samples.csv", index=False
    )

    # observed_data_out.csv
    df_obs = pd.DataFrame(obs_matrix, columns=OBS_NAMES)
    df_obs.insert(0, "t", t)
    df_obs.to_csv(out_dir / "observed_data_out.csv", index=False)

    # mean_trajectory.csv  — all 15 states
    mean_sol = odeint(nfkb_ode, y0=y0, t=t, rtol=1e-6, atol=1e-8, args=(mean_p,))
    cols_all = ["t"] + [f"y{i+1}" for i in range(N_STATES)]
    pd.DataFrame(np.column_stack([t, mean_sol]), columns=cols_all).to_csv(
        out_dir / "mean_trajectory.csv", index=False
    )

    # Per-state trajectory matrices. Observed-state exports include an estimated
    # observation-noise term; latent exports remain parameter-only.
    idx = posterior_indices(n_samples)
    latent_by_state = [np.zeros((N_TIMES, N_TRAJ_EXPORT)) for _ in range(N_STATES)]
    for k, i in enumerate(idx):
        sol_i = odeint(nfkb_ode, y0=y0, t=t, rtol=1e-5, atol=1e-7,
                       args=(post_p[:, i],))
        for s in range(N_STATES):
            latent_by_state[s][:, k] = sol_i[:, s]

    for s in range(N_STATES):
        traj = latent_by_state[s]
        if s in OBS_IDX:
            j = int(np.where(OBS_IDX == s)[0][0])
            traj, _ = noise_augmented_trajectories(traj, obs_matrix[:, j], mean_sol[:, s], seed=s)
        pd.DataFrame(traj, columns=[f"s{k}" for k in range(N_TRAJ_EXPORT)]).to_csv(
            out_dir / f"y{s+1}_trajectories.csv", index=False
        )
        pd.DataFrame(latent_by_state[s], columns=[f"s{k}" for k in range(N_TRAJ_EXPORT)]).to_csv(
            out_dir / f"y{s+1}_latent_trajectories.csv", index=False
        )

    print(f"Results exported to {out_dir}/")
    return mean_p


# ── Diagnostic plots (saved as PDF) ──────────────────────────────────────────
def save_plots(idata: az.InferenceData, mean_p: np.ndarray) -> None:
    out_dir  = RESULTS_DIR
    post_p   = stacked_posterior(idata)["p"].values
    rng      = np.random.default_rng(42)
    idx_plot = rng.integers(0, post_p.shape[1], size=75)
    mean_sol = odeint(nfkb_ode, y0=y0, t=t, rtol=1e-6, atol=1e-8, args=(mean_p,))

    # 1. Posterior predictive — 3×5 grid, one subplot per state
    fig, axes = plt.subplots(3, 5, figsize=(22, 13))
    for s, ax in enumerate(axes.flatten()):
        for i in idx_plot:
            sol_i = odeint(nfkb_ode, y0=y0, t=t, rtol=1e-5, atol=1e-7,
                           args=(post_p[:, i],))
            ax.plot(t, sol_i[:, s], alpha=0.08, c="C0", lw=0.7)
        ax.plot(t, mean_sol[:, s], c="C0", lw=2, label="mean")
        if s in OBS_IDX:
            j = int(np.where(OBS_IDX == s)[0][0])
            ax.scatter(t, obs_matrix[:, j], s=18, c="C1", zorder=5,
                       edgecolors="k", lw=0.4, label="obs")
            ax.legend(fontsize=6)
        ax.set_title(f"y{s+1}", fontsize=9)
        ax.set_xlabel("t (s)", fontsize=7)
        ax.tick_params(labelsize=6)
        ax.grid(True, lw=0.4)
    fig.suptitle("NF-κB — Posterior Predictive (ABC-SMC)", fontsize=13)
    fig.tight_layout()
    fig.savefig(out_dir / "nfkb_predictive.png", dpi=150)
    plt.close(fig)

    # 2. Posterior marginals — 5×6 grid (29 params + 1 empty)
    fig2, axes2 = plt.subplots(5, 6, figsize=(24, 16))
    axes2_flat = axes2.flatten()
    for k in range(N_PARAMS):
        ax = axes2_flat[k]
        samp = post_p[k, :]
        ax.hist(samp, bins=30, density=True, color="C0", edgecolor="w", alpha=0.8)
        ax.axvline(samp.mean(), color="r", lw=1.5, ls="--",
                   label=f"mean={samp.mean():.3g}")
        ax.axvline(TRUE_PARAMS[k], color="k", lw=1.5,
                   label=f"true={TRUE_PARAMS[k]:.3g}")
        ax.set_title(PARAM_NAMES[k], fontsize=9)
        ax.legend(fontsize=6)
        ax.tick_params(labelsize=6)
        ax.grid(True, lw=0.4)
    axes2_flat[N_PARAMS].set_visible(False)   # hide unused 30th panel
    fig2.suptitle("NF-κB — Posterior Marginals (ABC-SMC)", fontsize=13)
    fig2.tight_layout()
    fig2.savefig(out_dir / "nfkb_marginals.png", dpi=150)
    plt.close(fig2)

    print("Diagnostic plots saved.")


def report_smc_diagnostics(idata: az.InferenceData, mean_p: np.ndarray) -> None:
    out_dir = RESULTS_DIR
    n_chains, n_draws = posterior_chain_draw_sizes(idata)
    ess_floor = 100 * n_chains
    try:
        summary = az.summary(idata, var_names=["p"], hdi_prob=0.95)
    except TypeError:
        summary = az.summary(idata, var_names=["p"])
    summary.to_csv(out_dir / "smc_diagnostics.csv")

    ok = True
    print(f"\n=== SMC diagnostics ({n_chains} chains x {n_draws} draws = {n_chains*n_draws} samples) ===")
    print(f"\n  {'param':<8}  {'r_hat':>6}  {'ess_bulk':>9}  {'post_mean/true':>14}")
    for k in range(N_PARAMS):
        row = summary.loc[f"p[{k}]"]
        rhat = numeric_summary_value(row["r_hat"])
        ess = numeric_summary_value(row["ess_bulk"])
        ratio = mean_p[k] / TRUE_PARAMS[k]
        flag = "  <-- !" if rhat > 1.01 or ess < ess_floor else ""
        print(f"  {PARAM_NAMES[k]:<8}  {rhat:>6.3f}  {int(ess):>9}  {ratio:>14.3g}{flag}")

    bad_rhat = summary["r_hat"].map(numeric_summary_value).gt(1.01)
    bad_ess = summary["ess_bulk"].map(numeric_summary_value).lt(ess_floor)
    if bad_rhat.any():
        bad_names = [PARAM_NAMES[int(idx[2:-1])] for idx in summary.index[bad_rhat]]
        print(f"  WARNING: R-hat > 1.01 for {', '.join(bad_names)}.")
        ok = False
    if bad_ess.any():
        bad_names = [PARAM_NAMES[int(idx[2:-1])] for idx in summary.index[bad_ess]]
        print(f"  WARNING: ESS < {ess_floor} for {', '.join(bad_names)}.")
        ok = False

    prior_mean = 0.5 * (0.1 * TRUE_PARAMS + 4.0 * TRUE_PARAMS)
    prior_ratio = prior_mean / TRUE_PARAMS
    posterior_ratio = mean_p / TRUE_PARAMS
    near_prior_mean = np.abs(posterior_ratio - prior_ratio) < 0.25
    if np.mean(near_prior_mean) >= 0.5:
        print("  WARNING: many posterior means remain close to the broad-prior mean; interpret NF-kB parameter recovery as weakly identified.")
        ok = False

    print(f"\n  {'All checks passed.' if ok else 'Some checks flagged; do not report NF-kB parameters as trustworthy without qualification.'}")


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    idata  = run_sampling()
    mean_p = export_results(idata)
    save_plots(idata, mean_p)
    report_smc_diagnostics(idata, mean_p)
    try:
        print(az.summary(idata, var_names=["p"], hdi_prob=0.95).to_string())
    except TypeError:
        print(az.summary(idata, var_names=["p"]).to_string())
