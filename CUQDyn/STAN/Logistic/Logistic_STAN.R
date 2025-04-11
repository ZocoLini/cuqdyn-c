install.packages("StanHeaders")
install.packages("rstan")
install.packages("dplyr")
install.packages("tidyr")
install.packages("ggplot2")
install.packages("R.matlab")
install.packages("bayesplot")
install.packages("deSolve")
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

#Dataset

datos_in <- readMat('logistic_data_homoc_noise_0.10_size_10_data_1.mat')

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
p <- c(0.1, 100)

# Define the dynamic system
logistic_model <- function(time, state, parameters) {
  with(as.list(c(state, parameters)), {
    dy1 <- p[1]*y1*(1 - y1/p[2])
    list(c(dy1))
  })
}

# Define the initial conditions and the integration grid
initial_state <- c(y1 = 10)
times <- seq(0, max(pred1$time), by = 0.1)

# Solve the system
ode_result <- ode(y = initial_state, times = times, func = logistic_model, parms = p)
ode_df <- as.data.frame(ode_result)

true_values1 <- ode_df %>%
  gather(key = "state", value = "true_value", -time) %>%
  filter(state == "y1") %>%  
  mutate(well = rep(1, n())) 

######################################################################
######################################################################
######################################################################

svg("LOG_st1_STAN.svg")

p1 <- ggplot(pred1, aes(x = time, y = absorbance))
p1 <- p1 + geom_point(aes(color ="Observed values"), size = 1.5) +
  labs(x = "Time", y = "State Value") +
  theme_minimal() +
  theme(text = element_text(size =  16),
        axis.text = element_text(size = 26),
        axis.title = element_text(size = 26),
        legend.position = c(0.3, 1.05),
  )
p1 + geom_line(aes(x = time, y = median,color="Predicted model"),linewidth=1) +
  geom_ribbon(aes(ymin = lb, ymax = ub,fill = "Predictive region"), alpha = 0.25) +
  geom_line(data = true_values1, aes(x = time, y = true_value, color = "True model"), size = 1.2, linetype = "dashed")+
  scale_color_manual(values = c("Observed values" = "darkred", "Predicted model" = "blue", "True model" = "salmon")) +
  scale_fill_manual(values = c("Predictive region" = "dodgerblue"))+
  scale_x_continuous(breaks = seq(0, 100, by = 20)) +  
  scale_y_continuous(breaks = seq(0, 130, by = 40), limits = c(0, 130))

dev.off()




