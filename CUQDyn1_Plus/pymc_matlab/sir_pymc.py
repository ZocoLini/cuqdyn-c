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

# SIR epidemic model.
# Susceptible (S) and Recovered (R) are unobserved; Infected (I) is observed.
# Data: same CSV used by the CUQDyn1_Plus MATLAB examples.
#   true params: beta=0.002, gamma=0.5; IC=[990,10,0]; 10% proportional noise on I.
DATA_FILE   = "../EXAMPLES/SIR/data/sir_data.csv"
RESULTS_DIR = "results/sir"
os.makedirs(RESULTS_DIR, exist_ok=True)

true_beta  = 0.002
true_gamma = 0.5

df       = pd.read_csv(DATA_FILE)
t        = df["time"].values.astype(float)
X0       = np.array([df["y1"].iloc[0], df["y2"].iloc[0], df["y3"].iloc[0]])
observed = df["y2"].values.astype(float)    # Infected (state 2) at all 31 time points


def sir_ode(X, t, beta, gamma):
    dX = np.empty(3)
    dX[0] = -beta * X[0] * X[1]
    dX[1] =  beta * X[0] * X[1] - gamma * X[1]
    dX[2] =  gamma * X[1]
    return dX


def model_func(rng, beta, gamma, size=None):
    b = beta.item()  if hasattr(beta,  "item") else float(beta)
    g = gamma.item() if hasattr(gamma, "item") else float(gamma)
    try:
        sol = odeint(sir_ode, y0=X0, t=t, rtol=1e-5, atol=1e-7, args=(b, g))
        return sol[:, 1]    # Infected
    except Exception:
        return np.full(len(t), 1e6)


if __name__ == "__main__":
    # Prior bounds match CUQDyn1_Plus toolbox: lb=[0.0001,0.01], ub=[0.01,2.0]
    with pm.Model() as model_sir:
        beta  = pm.Uniform("beta",  lower=0.0001, upper=0.01)
        gamma = pm.Uniform("gamma", lower=0.01,   upper=2.0)

        sim = pm.Simulator("sim", model_func,
                           params=(beta, gamma),
                           epsilon=20, observed=observed)

        samples = pm.sample_smc(draws=1000, chains=4,
                                random_seed=RNG_SEED,
                                threshold=0.3, correlation_threshold=0.1)
        posterior = stacked_posterior(samples)

    mean_beta  = posterior["beta"].mean().item()
    mean_gamma = posterior["gamma"].mean().item()
    mean_sim   = odeint(sir_ode, y0=X0, t=t, rtol=1e-8, atol=1e-10,
                        args=(mean_beta, mean_gamma))

    state_labels = ["Susceptible (unobserved)", "Infected (observed)",
                    "Recovered (unobserved)"]
    state_colors = ["C3", "C0", "C2"]

    # Build trajectory ensemble. Observed-state exports include an estimated
    # observation-noise term; latent exports remain parameter-only.
    s_mat = np.zeros((len(t), N_TRAJ_EXPORT))
    i_latent = np.zeros((len(t), N_TRAJ_EXPORT))
    r_mat = np.zeros((len(t), N_TRAJ_EXPORT))
    idx_exp = posterior_indices(posterior.sizes["samples"])
    for k, i in enumerate(idx_exp):
        bi = float(posterior["beta"].values[i])
        gi = float(posterior["gamma"].values[i])
        si = odeint(sir_ode, y0=X0, t=t, rtol=1e-6, atol=1e-8, args=(bi, gi))
        s_mat[:, k] = si[:, 0]
        i_latent[:, k] = si[:, 1]
        r_mat[:, k] = si[:, 2]
    i_mat, sigma_infected = noise_augmented_trajectories(i_latent, observed, mean_sim[:, 1])

    # Posterior predictive plot — dual quantile bands
    traj_list = [s_mat, i_mat, r_mat]
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    for j, ax in enumerate(axes):
        c    = state_colors[j]
        tmat = traj_list[j]
        lo95 = np.percentile(tmat, 2.5,  axis=1)
        hi95 = np.percentile(tmat, 97.5, axis=1)
        lo50 = np.percentile(tmat, 25,   axis=1)
        hi50 = np.percentile(tmat, 75,   axis=1)
        ax.fill_between(t, lo95, hi95, color=c, alpha=0.20, label="95% PI")
        ax.fill_between(t, lo50, hi50, color=c, alpha=0.45, label="50% PI")
        ax.plot(t, mean_sim[:, j], color=c, linewidth=2.5, label="posterior mean")
        if j == 1:
            ax.plot(t, observed, "o", color=c, mec="k", markersize=4,
                    label="observed", zorder=5)
        ax.set_title(state_labels[j])
        ax.set_xlabel("time (days)"); ax.set_ylabel("population")
        ax.legend(fontsize=9)
    plt.suptitle("SIR model — ABC-SMC posterior predictive")
    plt.tight_layout()
    plt.savefig(os.path.join(RESULTS_DIR, "sir_predictive.pdf"))
    plt.close()

    if hasattr(az, "plot_posterior"):
        az.plot_posterior(samples)
        plt.tight_layout()
        plt.savefig(os.path.join(RESULTS_DIR, "sir_marginals.pdf"))
        plt.close()
    else:
        print("ArviZ plot_posterior unavailable; skipping sir_marginals.pdf")

    if hasattr(az, "plot_trace"):
        az.plot_trace(samples)
        plt.tight_layout()
        plt.savefig(os.path.join(RESULTS_DIR, "sir_trace.pdf"))
        plt.close()
    else:
        print("ArviZ plot_trace unavailable; skipping sir_trace.pdf")

    # Export CSVs for MATLAB
    b_s = posterior["beta"].values
    g_s = posterior["gamma"].values

    pd.DataFrame({"beta": b_s, "gamma": g_s}).to_csv(
        os.path.join(RESULTS_DIR, "posterior_samples.csv"), index=False)

    pd.DataFrame({"t": t, "susceptible": mean_sim[:, 0],
                  "infected": mean_sim[:, 1],
                  "recovered": mean_sim[:, 2]}).to_csv(
        os.path.join(RESULTS_DIR, "mean_trajectory.csv"), index=False)

    pd.DataFrame({"t": t, "infected_observed": observed}).to_csv(
        os.path.join(RESULTS_DIR, "observed_data_out.csv"), index=False)

    pd.DataFrame(s_mat).to_csv(
        os.path.join(RESULTS_DIR, "susceptible_trajectories.csv"), index=False)
    pd.DataFrame(i_mat).to_csv(
        os.path.join(RESULTS_DIR, "infected_trajectories.csv"), index=False)
    pd.DataFrame(i_latent).to_csv(
        os.path.join(RESULTS_DIR, "infected_latent_trajectories.csv"), index=False)
    pd.DataFrame(r_mat).to_csv(
        os.path.join(RESULTS_DIR, "recovered_trajectories.csv"), index=False)

    # ── SMC diagnostics ───────────────────────────────────────────────────────
    _nc, _nd = posterior_chain_draw_sizes(samples)
    _params  = ["beta", "gamma"]
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
    _lo      = np.percentile(i_mat,  2.5, axis=1)
    _hi      = np.percentile(i_mat, 97.5, axis=1)
    _cov     = np.mean((observed >= _lo) & (observed <= _hi))
    print(f"\n  Posterior predictive check (infected, noise-augmented 95% PI, {i_mat.shape[1]} samples):")
    print(f"  sigma_est = {sigma_infected:.4f}  (RMSE of posterior mean, added to parameter uncertainty)")
    print(f"  Coverage = {_cov*100:.0f}%  (nominal 95%)")
    if _cov < 0.85:
        print("  WARNING: coverage < 85% — posterior may be too narrow."); _ok = False
    print(f"\n  {'All checks passed.' if _ok else 'Some checks flagged — review warnings above.'}")
    # ──────────────────────────────────────────────────────────────────────────

    print(f"\nAll results saved to {RESULTS_DIR}/")
    print(f"True params — beta={true_beta}, gamma={true_gamma}")
    print(f"Posterior   — beta={mean_beta:.5f}, gamma={mean_gamma:.4f}")
