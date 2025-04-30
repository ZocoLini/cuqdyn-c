import matplotlib.pyplot as plt

x = [1, 2, 3, 4, 5]
y = [2.5, 3.6, 1.8, 4.0, 3.3]

# Create median data plot

plt.plot(x, y, 'r--')
plt.savefig("output/data_median.png", dpi=300)

# Create q_low data plot for each yn

plt.savefig("output/q_low.png", dpi=300)

# Create q_up data plot for each yn

plt.savefig("output/q_up.png", dpi=300)
