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
z <- array(NA_real_, dim = c(nSamples, 5, n_wells)) 

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
p <- c(5.93e-5, 2.96e-5, 2.05e-5, 27.5e-5, 4e-5)

# Define the dynamic system
model <- function(time, state, parameters) {
  with(as.list(c(state, parameters)), {
    dy1 <- -(p[1] + p[2]) * y1
    dy2 <- p[1] * y1
    dy3 <- p[2] * y1 - (p[3] + p[4]) * y3 + p[5] * y5
    dy4 <- p[3] * y3
    dy5 <- p[4] * y3 - p[5] * y5
    list(c(dy1, dy2, dy3, dy4, dy5))
  })
}

# Define the initial conditions and the integration grid
initial_state <- c(y1 = 100, y2 = 0, y3 = 0, y4 = 0, y5 = 0)
times <- seq(0, max(pred1$time), by = 0.1)

# Solve the system
ode_result <- ode(y = initial_state, times = times, func = model, parms = p)
ode_df <- as.data.frame(ode_result)

true_values1 <- ode_df %>%
  gather(key = "state", value = "true_value", -time) %>%
  filter(state == "y1") %>%  
  mutate(well = rep(1, n())) 

true_values2 <- ode_df %>%
  gather(key = "state", value = "true_value", -time) %>%
  filter(state == "y2") %>%  
  mutate(well = rep(1, n())) 

true_values3 <- ode_df %>%
  gather(key = "state", value = "true_value", -time) %>%
  filter(state == "y3") %>% 
  mutate(well = rep(1, n())) 

true_values4 <- ode_df %>%
  gather(key = "state", value = "true_value", -time) %>%
  filter(state == "y4") %>%  
  mutate(well = rep(1, n())) 

true_values5 <- ode_df %>%
  gather(key = "state", value = "true_value", -time) %>%
  filter(state == "y5") %>% 
  mutate(well = rep(1, n())) 


######################################################################
######################################################################
######################################################################

svg("AP_st1.svg")

p1 <- ggplot(pred1, aes(x = time, y = absorbance))
p1 <- p1 + geom_point(aes(color ="Observed values"), size = 1.5) +
  labs(x = "Time", y = "State Value") +
  theme_minimal() +
  theme(text = element_text(size = 12),
        axis.text = element_text(size = 20),
        axis.title = element_text(size = 20),
        legend.position ="none",
  )
p1 + geom_line(aes(x = time, y = median,color="Predicted model"),linewidth=1) +
  geom_ribbon(aes(ymin = lb, ymax = ub,fill = "Predictive region"), alpha = 0.25) +
  scale_color_manual(values = c("Observed values" = "darkred", "Predicted model" = "blue")) +
  scale_fill_manual(values = c("Predictive region" = "dodgerblue"))+
  scale_x_continuous(breaks = seq(0, 50000, by = 10000)) +  
  scale_y_continuous(breaks = seq(0, 115, by = 40), limits = c(-18, 119)) 

dev.off()


## STATE 2 ##

svg("AP_st2.svg")

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
        legend.position ="none",
  )
p2 + geom_line(aes(x = time, y = median,color="Predicted model"),linewidth=1) +
  geom_ribbon(aes(ymin = lb, ymax = ub,fill = "Predictive region"), alpha = 0.25) +
  scale_color_manual(values = c("Observed values" = "darkred", "Predicted model" = "blue")) +
  scale_fill_manual(values = c("Predictive region" = "dodgerblue"))+
  scale_x_continuous(breaks = seq(0, 50000, by = 10000)) +  
  scale_y_continuous(breaks = seq(0, 115, by = 40), limits = c(0, 80))

dev.off()


## STATE 3 ##

svg("AP_st3.svg")

xdata3 <- data.frame(absorbance = unlist(z[,3,1:n_wells]),well = as.vector(matrix(rep(1:n_wells,nSamples),nrow=nSamples,byrow=TRUE)),time = rep(ts,n_wells))
pred3 <- as.data.frame(estimates, pars = "z_pred") %>%
  gather(factor_key = TRUE) %>%
  group_by(key) %>%
  summarize(lb = quantile(value, probs = 0.025),
            median = quantile(value, probs = 0.5),
            ub = quantile(value, probs = 0.975)) %>%
  slice((2*nSamples+1):(3*nSamples)) %>%
  bind_cols(xdata3)

p3 <- ggplot(pred3, aes(x = time, y = absorbance))
p3 <- p3 + geom_point(aes(color ="Observed values"), size = 1.5) +
  labs(x = "Time", y = "State Value") +
  theme_minimal() +
  theme(text = element_text(size = 12),
        axis.text = element_text(size = 20),
        axis.title = element_text(size = 20),
        legend.position ="none",
  )
p3 + geom_line(aes(x = time, y = median,color="Predicted model"),linewidth=1) +
  geom_ribbon(aes(ymin = lb, ymax = ub,fill = "Predictive region"), alpha = 0.25) +
  scale_color_manual(values = c("Observed values" = "darkred", "Predicted model" = "blue")) +
  scale_fill_manual(values = c("Predictive region" = "dodgerblue")) +
  scale_x_continuous(breaks = seq(0, 50000, by = 10000)) +  
  scale_y_continuous(breaks = seq(0, 10, by = 2), limits = c(0, 10))

dev.off()


## STATE 4 ##

svg("AP_st4.svg")

xdata4 <- data.frame(absorbance = unlist(z[,4,1:n_wells]),well = as.vector(matrix(rep(1:n_wells,nSamples),nrow=nSamples,byrow=TRUE)),time = rep(ts,n_wells))
pred4 <- as.data.frame(estimates, pars = "z_pred") %>%
  gather(factor_key = TRUE) %>%
  group_by(key) %>%
  summarize(lb = quantile(value, probs = 0.025),
            median = quantile(value, probs = 0.5),
            ub = quantile(value, probs = 0.975)) %>%
  slice((3*nSamples+1):(4*nSamples)) %>%
  bind_cols(xdata4)

p4 <- ggplot(pred4, aes(x = time, y = absorbance))
p4 <- p4 + geom_point(aes(color ="Observed values"), size = 1.5) +
  labs(x = "Time", y = "State Value") +
  theme_minimal() +
  theme(text = element_text(size = 12),
        axis.text = element_text(size = 12),
        legend.title = element_blank(),
        legend.position = c(0.45, 1.05),
        legend.justification = c(0.45, 1.05),
        legend.direction = "vertical",
        legend.box = "vertical",
        legend.background = element_rect(fill = "white", color = "black", size = 0.5),
        strip.text = element_text(size = 8)
  )
p4 + geom_line(aes(x = time, y = median,color="Predicted model"),linewidth=1) +
  geom_ribbon(aes(ymin = lb, ymax = ub,fill = "Predictive region"), alpha = 0.25) +
  facet_wrap(~factor(well))+
  scale_color_manual(values = c("Observed values" = "darkred", "Predicted model" = "blue")) +
  scale_fill_manual(values = c("Predictive region" = "dodgerblue"))

dev.off()

## STATE 5 ##

svg("AP_st5.svg")

xdata5 <- data.frame(absorbance = unlist(z[,5,1:n_wells]),well = as.vector(matrix(rep(1:n_wells,nSamples),nrow=nSamples,byrow=TRUE)),time = rep(ts,n_wells))
pred5 <- as.data.frame(estimates, pars = "z_pred") %>%
  gather(factor_key = TRUE) %>%
  group_by(key) %>%
  summarize(lb = quantile(value, probs = 0.025),
            median = quantile(value, probs = 0.5),
            ub = quantile(value, probs = 0.975)) %>%
  slice((4*nSamples+1):(5*nSamples)) %>%
  bind_cols(xdata5)

p5 <- ggplot(pred5, aes(x = time, y = absorbance))
p5 <- p5 + geom_point(aes(color ="Observed values"), size = 1.5) +
  labs(x = "Time", y = "State Value") +
  theme_minimal() +
  theme(text = element_text(size = 12),
        axis.text = element_text(size = 12),
        legend.title = element_blank(),
        legend.position = c(0.45, 1.05),
        legend.justification = c(0.45, 1.05),
        legend.direction = "vertical",
        legend.box = "vertical",
        legend.background = element_rect(fill = "white", color = "black", size = 0.5),
        strip.text = element_text(size = 8)
  )
p5 + geom_line(aes(x = time, y = median,color="Predicted model"),linewidth=1) +
  geom_ribbon(aes(ymin = lb, ymax = ub,fill = "Predictive region"), alpha = 0.25) +
  facet_wrap(~factor(well))+
  scale_color_manual(values = c("Observed values" = "darkred", "Predicted model" = "blue")) +
  scale_fill_manual(values = c("Predictive region" = "dodgerblue"))

dev.off()

