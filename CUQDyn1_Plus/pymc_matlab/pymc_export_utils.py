import numpy as np


RNG_SEED = 42
N_TRAJ_EXPORT = 500


def numeric_summary_value(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return np.nan


def posterior_indices(n_samples, n_export=N_TRAJ_EXPORT, seed=RNG_SEED):
    rng = np.random.default_rng(seed)
    replace = n_samples < n_export
    return rng.choice(n_samples, size=n_export, replace=replace)


def posterior_dataset(idata):
    if hasattr(idata, "posterior"):
        posterior = idata.posterior
        if hasattr(posterior, "ds"):
            return posterior.ds
        return posterior
    return idata["posterior"].ds


def stacked_posterior(idata):
    return posterior_dataset(idata).stack(samples=("draw", "chain"))


def posterior_chain_draw_sizes(idata):
    posterior = posterior_dataset(idata)
    return posterior.sizes["chain"], posterior.sizes["draw"]


def noise_augmented_trajectories(latent, observed, mean_prediction, seed=0):
    sigma = float(np.sqrt(np.mean((mean_prediction - observed) ** 2)))
    rng = np.random.default_rng(seed)
    return latent + rng.normal(0.0, sigma, latent.shape), sigma
