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
# Prey (y1) observed, predator (y2) unobserved.
# True parameters: alpha=0.5, beta=0.02, delta=0.02, gamma=0.5
DATA_FILE   = "../EXAMPLES/LV/data/lv2_synthetic_data_noi10_partobs_1.csv"
RESULTS_DIR = "results/lv"
os.makedirs(RESULTS_DIR, exist_ok=True)

df       = pd.read_csv(DATA_FILE)
t        = df["time"].values.astype(float)
X0       = df.iloc[0, 1:].values.astype(float)   # [prey0=10, predator0=5]
observed = df["y1"].values.astype(float)           # prey at all 31 time points


def lv_ode(X, t, alpha, beta, delta, gamma):
    dX = np.empty(2)
    dX[0] = (alpha - beta * X[1]) * X[0]
    dX[1] = (delta * X[0] - gamma) * X[1]
    return dX


def model_func(rng, alpha, beta, delta, gamma, size=None):
    a = alpha.item() if hasattr(alpha, "item") else float(alpha)
    b = beta.item()  if hasattr(beta,  "item") else float(beta)
    d = delta.item() if hasattr(delta, "item") else float(delta)
    g = gamma.item() if hasattr(gamma, "item") else float(gamma)
    try:
        sol = odeint(lv_ode, y0=X0, t=t, rtol=1e-5, atol=1e-7, args=(a, b, d, g))
        return sol[:, 0]
    except Exception:
        return np.full(len(t), 1e6)


if __name__ == "__main__":
    # Prior bounds match CUQDyn1_Plus toolbox: lb=true*0.2, ub=true*2.0
    with pm.Model() as model_lv:
        alpha = pm.Uniform("alpha", lower=0.10,  upper=1.00)
        beta  = pm.Uniform("beta",  lower=0.004, upper=0.04)
        delta = pm.Uniform("delta", lower=0.004, upper=0.04)
        gamma = pm.Uniform("gamma", lower=0.10,  upper=1.00)

        sim = pm.Simulator("sim", model_func,
                           params=(alpha, beta, delta, gamma),
                           epsilon=3, observed=observed)

    #    samples = pm.sample_smc(draws=1000, chains=4,
    #                            threshold=0.5, correlation_threshold=0.1)

        samples = pm.sample_smc(draws=4000, chains=4,
                                random_seed=RNG_SEED,
                                threshold=0.6, correlation_threshold=0.01)

        posterior = stacked_posterior(samples)

    # Mean trajectory (both states)
    mean_a = posterior["alpha"].mean().item()
    mean_b = posterior["beta"].mean().item()
    mean_d = posterior["delta"].mean().item()
    mean_g = posterior["gamma"].mean().item()
    mean_sim = odeint(lv_ode, y0=X0, t=t, rtol=1e-8, atol=1e-10,
                      args=(mean_a, mean_b, mean_d, mean_g))

    # Build trajectory ensemble. Observed-state exports include an estimated
    # observation-noise term; latent exports remain parameter-only.
    prey_latent = np.zeros((len(t), N_TRAJ_EXPORT))
    pred_mat = np.zeros((len(t), N_TRAJ_EXPORT))
    idx_exp  = posterior_indices(posterior.sizes["samples"])
    for k, i in enumerate(idx_exp):
        ai = float(posterior["alpha"].values[i])
        bi = float(posterior["beta"].values[i])
        di = float(posterior["delta"].values[i])
        gi = float(posterior["gamma"].values[i])
        si = odeint(lv_ode, y0=X0, t=t, rtol=1e-6, atol=1e-8, args=(ai, bi, di, gi))
        prey_latent[:, k] = si[:, 0]
        pred_mat[:, k] = si[:, 1]
    prey_mat, sigma_prey = noise_augmented_trajectories(prey_latent, observed, mean_sim[:, 0])

    # Posterior predictive plot — dual quantile bands
    state_labels_plot = ["Prey (observed)", "Predator (unobserved)"]
    traj_list         = [prey_mat, pred_mat]

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    for j, ax in enumerate(axes):
        c    = f"C{j}"
        tmat = traj_list[j]
        lo95 = np.percentile(tmat, 2.5,  axis=1)
        hi95 = np.percentile(tmat, 97.5, axis=1)
        lo50 = np.percentile(tmat, 25,   axis=1)
        hi50 = np.percentile(tmat, 75,   axis=1)
        ax.fill_between(t, lo95, hi95, color=c, alpha=0.20, label="95% PI")
        ax.fill_between(t, lo50, hi50, color=c, alpha=0.45, label="50% PI")
        ax.plot(t, mean_sim[:, j], color=c, linewidth=2.5, label="posterior mean")
        if j == 0:
            ax.plot(t, observed, "o", color=c, mec="k", markersize=6,
                    label="observed", zorder=5)
        ax.set_xlabel("time"); ax.set_ylabel("population")
        ax.set_title(state_labels_plot[j], fontsize=11)
        ax.legend(fontsize=9)
    plt.suptitle("Lotka-Volterra — ABC-SMC posterior predictive")
    plt.tight_layout()
    plt.savefig(os.path.join(RESULTS_DIR, "lv_predictive.pdf"))
    plt.close()

    if hasattr(az, "plot_posterior"):
        az.plot_posterior(samples)
        plt.tight_layout()
        plt.savefig(os.path.join(RESULTS_DIR, "lv_marginals.pdf"))
        plt.close()
    else:
        print("ArviZ plot_posterior unavailable; skipping lv_marginals.pdf")

    if hasattr(az, "plot_trace"):
        az.plot_trace(samples)
        plt.tight_layout()
        plt.savefig(os.path.join(RESULTS_DIR, "lv_trace.pdf"))
        plt.close()
    else:
        print("ArviZ plot_trace unavailable; skipping lv_trace.pdf")

    # Export CSVs for MATLAB
    a_s = posterior["alpha"].values
    b_s = posterior["beta"].values
    d_s = posterior["delta"].values
    g_s = posterior["gamma"].values

    pd.DataFrame({"alpha": a_s, "beta": b_s,
                  "delta": d_s, "gamma": g_s}).to_csv(
        os.path.join(RESULTS_DIR, "posterior_samples.csv"), index=False)

    pd.DataFrame({"t": t, "prey": mean_sim[:, 0],
                  "predator": mean_sim[:, 1]}).to_csv(
        os.path.join(RESULTS_DIR, "mean_trajectory.csv"), index=False)

    pd.DataFrame({"t": t, "prey_observed": observed}).to_csv(
        os.path.join(RESULTS_DIR, "observed_data_out.csv"), index=False)

    pd.DataFrame(prey_mat).to_csv(
        os.path.join(RESULTS_DIR, "prey_trajectories.csv"), index=False)
    pd.DataFrame(prey_latent).to_csv(
        os.path.join(RESULTS_DIR, "prey_latent_trajectories.csv"), index=False)
    pd.DataFrame(pred_mat).to_csv(
        os.path.join(RESULTS_DIR, "predator_trajectories.csv"), index=False)

    # ── SMC diagnostics ───────────────────────────────────────────────────────
    _nc, _nd = posterior_chain_draw_sizes(samples)
    _params  = ["alpha", "beta", "delta", "gamma"]
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
    _lo       = np.percentile(prey_mat,  2.5, axis=1)
    _hi       = np.percentile(prey_mat, 97.5, axis=1)
    _cov      = np.mean((observed >= _lo) & (observed <= _hi))
    print(f"\n  Posterior predictive check (prey, noise-augmented 95% PI, {prey_mat.shape[1]} samples):")
    print(f"  sigma_est = {sigma_prey:.4f}  (RMSE of posterior mean, added to parameter uncertainty)")
    print(f"  Coverage = {_cov*100:.0f}%  (nominal 95%)")
    if _cov < 0.85:
        print("  WARNING: coverage < 85% — posterior may be too narrow."); _ok = False
    print(f"\n  {'All checks passed.' if _ok else 'Some checks flagged — review warnings above.'}")
    # ──────────────────────────────────────────────────────────────────────────

    print(f"\nAll results saved to {RESULTS_DIR}/")
