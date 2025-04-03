library(rstan)
library(dplyr)
library(tidyr)
library(ggplot2)
library(R.matlab)
library(deSolve)

rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())

# Dataset
datos_in <- read.csv("measurementData.csv")
time<-datos_in[,1]
absorbance1 <- datos_in[,2]
absorbance2 <- datos_in[,3]
absorbance3 <- datos_in[,4]
absorbance4 <- datos_in[,5]
absorbance5 <- datos_in[,6]

n_dat <- length(absorbance1)
well <- rep("A1", n_dat)

long_growthdata <- data.frame(time, absorbance1, absorbance2, absorbance3, absorbance4, absorbance5, well)

stan_file <- 'AP_STAN.stan'
alpha_pinene_stan <- stan_model(file = stan_file)

glimpse(long_growthdata)

# Data visualization
ggplot(long_growthdata, aes(time, absorbance1, group = well)) +
  geom_line() +
  theme_bw()
ggplot(long_growthdata, aes(time, absorbance2, group = well)) +
  geom_line() +
  theme_bw()
ggplot(long_growthdata, aes(time, absorbance3, group = well)) +
  geom_line() +
  theme_bw()
ggplot(long_growthdata, aes(time, absorbance4, group = well)) +
  geom_line() +
  theme_bw()
ggplot(long_growthdata, aes(time, absorbance5, group = well)) +
  geom_line() +
  theme_bw()

n_wells = 1
nSamples = n_dat - 1

y0 <- c(absorbance1[1], absorbance2[1], absorbance3[1], absorbance4[1], absorbance5[1]) # Initial conditions
t0 <- 0.0
ts <- long_growthdata %>% filter(time > 0) %>% select(time) %>% unlist
z <- array(NA_real_, dim = c(nSamples, 5, n_wells)) # Cambia el tamaño del array según el número de especies

z[, 1, 1] <- absorbance1[-1]  
z[, 2, 1] <- absorbance2[-1]
z[, 3, 1] <- absorbance3[-1]  
z[, 4, 1] <- absorbance4[-1]
z[, 5, 1] <- absorbance5[-1]  

estimates <- sampling(object = alpha_pinene_stan,
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
