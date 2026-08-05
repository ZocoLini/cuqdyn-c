import os
import platform

if platform.system() == "Windows":
    os.environ["PYTENSOR_FLAGS"] = f"compiledir={os.path.abspath('.pytensor_cache')},cxx="

import arviz as az
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pymc as pm
import pandas as pd
from scipy.integrate import odeint
from pymc_export_utils import RNG_SEED, N_TRAJ_EXPORT, noise_augmented_trajectories, numeric_summary_value, posterior_chain_draw_sizes, posterior_indices, stacked_posterior

# Data: same CSV used by CUQDyn1_Plus toolbox
# States y1-y4 observed; y5 (delta-3-carene) unobserved.
# True parameters: [5.93e-05, 2.96e-05, 2.05e-05, 2.75e-04, 4.00e-05]
DATA_FILE   = "../EXAMPLES/AP/data/AP_measurementData_1_4.csv"
RESULTS_DIR = "results/ap"
os.makedirs(RESULTS_DIR, exist_ok=True)

df  = pd.read_csv(DATA_FILE)
t   = df["time"].values.astype(float)
X0  = df.iloc[0, 1:].values.astype(float)    # all 5 states at t=0

obs_cols      = ["y1", "y2", "y3", "y4"]
obs_matrix    = df[obs_cols].values.astype(float)        # (9, 4)
# Normalise each state by its time-mean so all four states contribute equally
# to the ABC distance regardless of scale (y1 peaks at 106, y4 at 4.3).
norms         = obs_matrix.mean(axis=0)                  # (4,)
observed_flat = (obs_matrix / norms).flatten()           # (36,) normalised


def ap_ode(X, t, p1, p2, p3, p4, p5):
    dX = np.empty(5)
    dX[0] = -(p1 + p2) * X[0]
    dX[1] = p1 * X[0]
    dX[2] = p2 * X[0] - (p3 + p4) * X[2] + p5 * X[4]
    dX[3] = p3 * X[2]
    dX[4] = p4 * X[2] - p5 * X[4]
    return dX


def model_func(rng, p1, p2, p3, p4, p5, size=None):
    def s(x): return x.item() if hasattr(x, "item") else float(x)
    try:
        sol = odeint(ap_ode, y0=X0, t=t, rtol=1e-4, atol=1e-8,
                     args=(s(p1), s(p2), s(p3), s(p4), s(p5)))
        return (sol[:, :4] / norms).flatten()    # normalised, row-major
    except Exception:
        return np.full(len(observed_flat), 1e6)


if __name__ == "__main__":
    # Prior bounds match current CUQDyn1_Plus AP examples: lb=true*0.05, ub=true*5.0
    with pm.Model() as model_ap:
        p1 = pm.Uniform("p1", lower=2.965e-06, upper=2.965e-04)
        p2 = pm.Uniform("p2", lower=1.480e-06, upper=1.480e-04)
        p3 = pm.Uniform("p3", lower=1.025e-06, upper=1.025e-04)
        p4 = pm.Uniform("p4", lower=1.375e-05, upper=1.375e-03)
        p5 = pm.Uniform("p5", lower=2.000e-06, upper=2.000e-04)

        sim = pm.Simulator("sim", model_func,
                           params=(p1, p2, p3, p4, p5),
                           epsilon=0.5, observed=observed_flat)

        samples = pm.sample_smc(draws=1000, chains=4,
                                random_seed=RNG_SEED,
                                threshold=0.5, correlation_threshold=0.1)
        posterior = stacked_posterior(samples)

    # Mean trajectory (all 5 states)
    mean_p = [posterior[f"p{k+1}"].mean().item() for k in range(5)]
    mean_sim = odeint(ap_ode, y0=X0, t=t, rtol=1e-8, atol=1e-10,
                      args=tuple(mean_p))

    state_labels = ["y1 (observed)", "y2 (observed)", "y3 (observed)",
                    "y4 (observed)", "y5 (unobserved)"]
    state_colors = ["C0", "C1", "C2", "C3", "C4"]

    # Build trajectory ensemble. Observed-state exports include an estimated
    # observation-noise term; latent exports remain parameter-only.
    latent_mats = [np.zeros((len(t), N_TRAJ_EXPORT)) for _ in range(5)]
    rng_exp = np.random.default_rng(42)
    idx_exp = posterior_indices(posterior.sizes["samples"])
    for k, i in enumerate(idx_exp):
        pi = [float(posterior[f"p{k2+1}"].values[i]) for k2 in range(5)]
        si = odeint(ap_ode, y0=X0, t=t, rtol=1e-4, args=tuple(pi))
        for j in range(5):
            latent_mats[j][:, k] = si[:, j]
    traj_mats = list(latent_mats)
    sigma_obs = []
    for j in range(4):
        traj_mats[j], sigma_j = noise_augmented_trajectories(latent_mats[j], obs_matrix[:, j], mean_sim[:, j], seed=j)
        sigma_obs.append(sigma_j)

    # Posterior predictive plot — dual quantile bands
    fig, axes = plt.subplots(1, 5, figsize=(22, 5))
    for j, ax in enumerate(axes):
        c    = state_colors[j]
        tmat = traj_mats[j]
        lo95 = np.percentile(tmat, 2.5,  axis=1)
        hi95 = np.percentile(tmat, 97.5, axis=1)
        lo50 = np.percentile(tmat, 25,   axis=1)
        hi50 = np.percentile(tmat, 75,   axis=1)
        ax.fill_between(t, lo95, hi95, color=c, alpha=0.20, label="95% PI")
        ax.fill_between(t, lo50, hi50, color=c, alpha=0.45, label="50% PI")
        ax.plot(t, mean_sim[:, j], color=c, linewidth=2.5, label="posterior mean")
        if j < 4:
            ax.plot(t, obs_matrix[:, j], "o", color=c, mec="k",
                    markersize=6, label="observed", zorder=5)
        ax.set_title(state_labels[j], fontsize=10)
        ax.set_xlabel("time"); ax.set_ylabel("concentration")
        ax.legend(fontsize=8)
    plt.suptitle("Alpha-pinene — ABC-SMC posterior predictive")
    plt.tight_layout()
    plt.savefig(os.path.join(RESULTS_DIR, "ap_predictive.pdf"))
    plt.close()

    if hasattr(az, "plot_posterior"):
        az.plot_posterior(samples)
        plt.tight_layout()
        plt.savefig(os.path.join(RESULTS_DIR, "ap_marginals.pdf"))
        plt.close()
    else:
        print("ArviZ plot_posterior unavailable; skipping ap_marginals.pdf")

    if hasattr(az, "plot_trace"):
        az.plot_trace(samples)
        plt.tight_layout()
        plt.savefig(os.path.join(RESULTS_DIR, "ap_trace.pdf"))
        plt.close()
    else:
        print("ArviZ plot_trace unavailable; skipping ap_trace.pdf")

    # Export CSVs for MATLAB
    param_df = pd.DataFrame({f"p{k+1}": posterior[f"p{k+1}"].values
                              for k in range(5)})
    param_df.to_csv(os.path.join(RESULTS_DIR, "posterior_samples.csv"), index=False)

    traj_df = pd.DataFrame({"t": t})
    for j in range(5):
        traj_df[f"y{j+1}"] = mean_sim[:, j]
    traj_df.to_csv(os.path.join(RESULTS_DIR, "mean_trajectory.csv"), index=False)

    obs_df = pd.DataFrame({"t": t})
    for j, col in enumerate(obs_cols):
        obs_df[col] = obs_matrix[:, j]
    obs_df.to_csv(os.path.join(RESULTS_DIR, "observed_data_out.csv"), index=False)

    state_names = ["y1", "y2", "y3", "y4", "y5"]
    for j in range(5):
        pd.DataFrame(traj_mats[j]).to_csv(
            os.path.join(RESULTS_DIR, f"{state_names[j]}_trajectories.csv"),
            index=False)
        pd.DataFrame(latent_mats[j]).to_csv(
            os.path.join(RESULTS_DIR, f"{state_names[j]}_latent_trajectories.csv"),
            index=False)

    # ── SMC diagnostics ───────────────────────────────────────────────────────
    _nc, _nd = posterior_chain_draw_sizes(samples)
    _params  = [f"p{k+1}" for k in range(5)]
    _summ    = az.summary(samples, var_names=_params)
    _ok      = True
    print(f"\n=== SMC diagnostics ({_nc} chains × {_nd} draws = {_nc*_nd} samples) ===")
    print(f"\n  {'param':<8}  {'r_hat':>6}  {'ess_bulk':>9}")
    for _p in _params:
        _r = numeric_summary_value(_summ.loc[_p, "r_hat"])
        _e = numeric_summary_value(_summ.loc[_p, "ess_bulk"])
        print(f"  {_p:<8}  {_r:>6.3f}  {int(_e):>9}{'  <-- !' if _r > 1.01 else ''}")
    if _summ["r_hat"].map(numeric_summary_value).gt(1.01).any():
        print("  WARNING: R-hat > 1.01 — consider more draws or chains."); _ok = False
    if _summ["ess_bulk"].map(numeric_summary_value).lt(100 * _nc).any():
        print(f"  WARNING: ESS < {100*_nc} — consider more draws."); _ok = False
    _rng_ppc_ap = np.random.default_rng(0)
    print(f"\n  Posterior predictive check (noise-augmented 95% PI, {traj_mats[0].shape[1]} samples):")
    print(f"  {'state':<6}  {'RMSE':>8}  {'coverage':>9}")
    for _j, _name in enumerate(obs_cols):
        _rmse_j  = sigma_obs[_j]
        _lo      = np.percentile(traj_mats[_j],  2.5, axis=1)
        _hi      = np.percentile(traj_mats[_j], 97.5, axis=1)
        _cov     = np.mean((obs_matrix[:, _j] >= _lo) & (obs_matrix[:, _j] <= _hi))
        _flag    = "  <-- !" if _cov < 0.85 else ""
        print(f"  {_name:<6}  {_rmse_j:>8.4f}  {_cov*100:>8.0f}%{_flag}")
        if _cov < 0.85: _ok = False
    print(f"\n  {'All checks passed.' if _ok else 'Some checks flagged — review warnings above.'}")
    # ──────────────────────────────────────────────────────────────────────────

    print(f"\nAll results saved to {RESULTS_DIR}/")
