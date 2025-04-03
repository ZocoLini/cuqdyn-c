library(rstan)
library(dplyr)
library(tidyr)
library(ggplot2)
library(R.matlab)

rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())

#Dataset

datos_in <- readMat('logistic_data_homoc_noise_0.01_size_50_data_1.mat')

time <- datos_in$data.matrix[,1] # Time points
absorbance <- datos_in$data.matrix[,2] # State values
n_dat <- length(absorbance)
well <- rep("A1",n_dat)

long_growthdata=data.frame(time,absorbance,well)

stan_file <- 'Logistic_STAN.stan'
logisticgrowth_stan <- stan_model(file = stan_file)

glimpse(long_growthdata)

ggplot(long_growthdata,aes(time,absorbance,group=well)) +
  geom_line() + 
  theme_bw()

n_wells = 1
nSamples = n_dat - 1

y0 = array(absorbance[1], dim = 1)
t0 = 0.0
ts = filter(long_growthdata,time>0) %>% select(time) %>% unlist
z = filter(long_growthdata,time>0) %>% select(-time) %>% .[,1:n_wells, drop = FALSE]
estimates <- sampling(object = logisticgrowth_stan,
                      data = list (
                        T  = nSamples,
                        n_wells = n_wells,
                        y0 = y0,
                        z  = z,
                        t0 = t0,
                        ts = ts
                      ),
                      seed = 123,
                      chains = 4,
                      iter = 4000,
                      warmup = 2000,
                      control = list(adapt_delta = 0.95,max_treedepth = 15) 
)

parametersToPlot = c("theta","sigma","lp__")
print(estimates, pars = parametersToPlot)
