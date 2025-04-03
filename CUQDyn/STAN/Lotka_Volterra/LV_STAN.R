library(rstan)
library(dplyr)
library(tidyr)
library(ggplot2)
library(R.matlab)

rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())

# Dataset
datos_in <- readMat('lotka_volterra_data_homoc_noise_0.10_size_31_data_2.mat')
time <- datos_in$data.matrix[,1] # Time points
absorbance1 <- datos_in$data.matrix[,2] # State values
absorbance2 <- datos_in$data.matrix[,3] 
n_dat <- length(absorbance1)
well <- rep("A1", n_dat)

long_growthdata <- data.frame(time, absorbance1, absorbance2, well)

stan_file <- 'LV_STAN.stan'
lotka_volterra_stan <- stan_model(file = stan_file)

glimpse(long_growthdata)

# Data visualization
ggplot(long_growthdata, aes(time, absorbance1, absorbance2, group = well)) +
  geom_line() +
  geom_line(aes(y = absorbance2, color = "red")) +
  theme_bw()

n_wells = 1
nSamples = n_dat - 1

y0 <- c(absorbance1[1], absorbance2[1]) # Initial conditions
t0 <- 0.0
ts <- long_growthdata %>% filter(time > 0) %>% select(time) %>% unlist
z <- array(NA_real_, dim = c(nSamples, 2, n_wells))
z[, 1, 1] <- absorbance1[-1]
z[, 2, 1] <- absorbance2[-1]

estimates <- sampling(object = lotka_volterra_stan,
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
