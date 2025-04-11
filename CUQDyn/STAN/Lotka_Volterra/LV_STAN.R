library(StanHeaders)
library(rstan)
library(dplyr)
library(tidyr)
library(ggplot2)
library(R.matlab)
library(bayesplot)
library(deSolve)

rstan_options(auto_write = TRUE)
options(mc.cores = parallel::detectCores())

# Dataset
datos_in <- readMat('lotka_volterra_data_homoc_noise_0.10_size_30_data_1.mat')
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

## STATE 1 ##

xdata1 <- data.frame(absorbance = unlist(z[,1,1:n_wells]),well = as.vector(matrix(rep(1:n_wells,nSamples),nrow=nSamples,byrow=TRUE)),time = rep(ts,n_wells))
pred1 <- as.data.frame(estimates, pars = "z_pred") %>%
  gather(factor_key = TRUE) %>%
  group_by(key) %>%
  summarize(lb = quantile(value, probs = 0.025),
            median = quantile(value, probs = 0.5),
            ub = quantile(value, probs = 0.975)) %>%
  slice(1:nSamples) %>%
  bind_cols(xdata1)

######################################################################
############################# TRUE MODEL #############################
######################################################################

# Define the true parameters
p <- c(0.5, 0.02, 0.02, 0.5)

# Define the dynamic system
lotka_volterra <- function(time, state, parameters) {
  with(as.list(c(state, parameters)), {
    dy1 <- (p[1] - p[2] * y2) * y1
    dy2 <- (p[3] * y1 - p[4]) * y2
    list(c(dy1, dy2))
  })
}

# Define the initial conditions and the integration grid
initial_state <- c(y1 = 10, y2 = 5)
times <- seq(0, max(pred1$time), by = 0.1)

# Solve the system
ode_result <- ode(y = initial_state, times = times, func = lotka_volterra, parms = p)
ode_df <- as.data.frame(ode_result)

true_values1 <- ode_df %>%
  gather(key = "state", value = "true_value", -time) %>%
  filter(state == "y1") %>%  
  mutate(well = rep(1, n()))

true_values2 <- ode_df %>%
  gather(key = "state", value = "true_value", -time) %>%
  filter(state == "y2") %>% 
  mutate(well = rep(1, n())) 



######################################################################
######################################################################
######################################################################


svg("LV_st1_STAN.svg")

p1 <- ggplot(pred1, aes(x = time, y = absorbance))
p1 <- p1 + geom_point(aes(color ="Observed values"), size = 1.5) +
  labs(x = "Time", y = "State Value") +
  theme_minimal() +
  theme(text = element_text(size = 12),
        axis.text = element_text(size = 20),
        axis.title = element_text(size = 20),
        legend.position = "none",
  )
p1 + geom_line(aes(x = time, y = median,color="Predicted model"),linewidth=1) +
  geom_ribbon(aes(ymin = lb, ymax = ub,fill = "Predictive region"), alpha = 0.25) +
  geom_line(data = true_values1, aes(x = time, y = true_value, color = "True model"), size = 1.2, linetype = "dashed")+
  scale_color_manual(values = c("Observed values" = "darkred", "Predicted model" = "blue", "True model" = "salmon")) +
  scale_fill_manual(values = c("Predictive region" = "dodgerblue"))+
  scale_x_continuous(breaks = seq(0, 50, by = 10)) +  
  scale_y_continuous(breaks = seq(0, 115, by = 40), limits = c(-5, 90))

dev.off()

## STATE 2 ##

svg("LV_st2_STAN.svg")

xdata2 <- data.frame(absorbance = unlist(z[,2,1:n_wells]),well = as.vector(matrix(rep(1:n_wells,nSamples),nrow=nSamples,byrow=TRUE)),time = rep(ts,n_wells))
pred2 <- as.data.frame(estimates, pars = "z_pred") %>%
  gather(factor_key = TRUE) %>%
  group_by(key) %>%
  summarize(lb = quantile(value, probs = 0.025),
            median = quantile(value, probs = 0.5),
            ub = quantile(value, probs = 0.975)) %>%
  slice((nSamples+1):(2*nSamples)) %>%
  bind_cols(xdata2)

p2 <- ggplot(pred2, aes(x = time, y = absorbance))
p2 <- p2 + geom_point(aes(color ="Observed values"), size = 1.5) +
  labs(x = "Time", y = "State Value") +
  theme_minimal() +
  theme(text = element_text(size = 12),
        axis.text = element_text(size = 20),
        axis.title = element_text(size = 20),
        legend.position = "none",
  )
p2 + geom_line(aes(x = time, y = median,color="Predicted model"),linewidth=1) +
  geom_ribbon(aes(ymin = lb, ymax = ub,fill = "Predictive region"), alpha = 0.25) +
  geom_line(data = true_values2, aes(x = time, y = true_value, color = "True model"), size = 1.2, linetype = "dashed")+
  scale_color_manual(values = c("Observed values" = "darkred", "Predicted model" = "blue", "True model" = "salmon")) +
  scale_fill_manual(values = c("Predictive region" = "dodgerblue"))+
  scale_x_continuous(breaks = seq(0, 50, by = 10)) +  
  scale_y_continuous(breaks = seq(0, 115, by = 40), limits = c(-5, 90))

dev.off()

