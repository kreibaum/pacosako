# Written by ChatGPT 4 on 2023-10-31.
# Modified by Rolf Kreibaum.
import pandas as pd
import matplotlib.pyplot as plt

# Load the updated CSV file for analysis
file_path = 'paco_2_performance.csv'
data = pd.read_csv(file_path)

# Assuming the timings are in the second column, if not, this line may need adjustment.
timings = data.iloc[:, 1]

# Calculate the 90th and 95th percentiles and the average of the timing data
p50 = timings.quantile(0.50)
p90 = timings.quantile(0.90)
p95 = timings.quantile(0.95)
average_timing = timings.mean()

# Remove the top 5% of the data to get a better view of the histogram
timings = timings[timings < p95]

# Generate a histogram of the timing data
plt.figure(figsize=(10, 6))
histogram_plot = plt.hist(timings, bins=50, alpha=0.7,
                          color='blue', edgecolor='black')

# Mark the 90th and 95th percentiles and average on the histogram
plt.axvline(p50, color='black', linestyle='dashed', linewidth=1)
plt.axvline(p90, color='red', linestyle='dashed', linewidth=1)
plt.axvline(p95, color='green', linestyle='dashed', linewidth=1)
# plt.axvline(average_timing, color='purple', linestyle='dashed', linewidth=1)

# Annotate the lines
plt.text(p50+10, plt.ylim()[1]*0.95, f'P50: {round(p50)}', color='black')
plt.text(p90+10, plt.ylim()[1]*0.9, f'P90: {round(p90)}', color='red')
plt.text(p95+10, plt.ylim()[1]*0.85, f'P95: {round(p95)}', color='green')
# plt.text(average_timing+10, plt.ylim()[1]*0.8,
#         f'Mean: {round(average_timing)}', color='purple')

# Adding labels and title
plt.xlabel('Timings (milliseconds)')
plt.ylabel('Frequency')
plt.title('Histogram of Timings')

# Save the histogram to a file
histogram_path = 'timing_histogram.png'
plt.savefig(histogram_path)

# Output the calculated values and the path to the saved histogram image
p90, p95, average_timing, histogram_path
