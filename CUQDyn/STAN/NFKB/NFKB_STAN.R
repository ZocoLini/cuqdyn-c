library(rstan)
library(dplyr)
library(tidyr)
library(ggplot2)
library(R.matlab)
library(deSolve)

rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())

# Dataset
datos_in <- readMat('nfkb_pe_data_homoc.mat')
time <- datos_in$data.matrix[,1]
observed_states <- readMat('observed_data.mat')$observed.data
n_dat <- nrow(observed_states)
well <- rep("A1", n_dat)

long_growthdata <- data.frame(time, observed_states, well)

stan_file <- 'NFKB_STAN.stan'
nfkb_pe_stan <- stan_model(file = stan_file)

glimpse(long_growthdata)

# Data visualization
ggplot(long_growthdata, aes(x = time, y = observed_states[,1], group = well)) +
  geom_line() +
  theme_bw()

n_wells = 1
nSamples = n_dat - 1

y0 <- c(0.2, 0, 0, 0, 0, 3.155e-004, 2.2958e-003, 4.78285e-003, 2.8697e-006, 2.50663e-003,
        3.43573e-003, 2.86971e-006, 0.06, 7.888e-005, 2.86971e-006) # Initial conditions
t0 <- 0.0
ts <- long_growthdata %>% filter(time > 0) %>% select(time) %>% unlist
z <- array(NA_real_, dim = c(nSamples, 6, n_wells))
for (i in 1:6) {
  z[, i, 1] <- observed_states[-1, i]
}

estimates <- sampling(object = nfkb_pe_stan,
                      data = list(
                        T = nSamples,
                        n_wells = n_wells,
                        y0 = y0,
                        z = z,
                        t0 = t0,
                        ts = ts
                      ),
                      seed = 1234,
                      chains = 4,
                      iter = 1000,
                      warmup = 500,
                      control = list(adapt_delta = 0.95, max_treedepth = 15)
)

parametersToPlot = c("params", "sigma", "lp__")
print(estimates, pars = parametersToPlot)
