import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import matplotlib.pyplot as plt

# Load dataset
df = pd.read_csv("kerala_energy_1year.csv")

# Select features
features = [
    'Global_active_power',
    'Global_intensity',
    'Voltage',
    'Sub_metering_1',
    'Sub_metering_2',
    'Sub_metering_3',
    'Sub_metering_4'
]

X = df[features]

# Normalize
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# Train model
model = IsolationForest(
    n_estimators=100,
    contamination=0.05,
    random_state=42
)

df['anomaly'] = model.fit_predict(X_scaled)
df['anomaly'] = df['anomaly'].apply(lambda x: 1 if x == -1 else 0)

print(df[['Global_active_power', 'anomaly']].head())
print(df['anomaly'].value_counts())

# 🔽🔽🔽 PASTE VISUALIZATION CODE HERE 🔽🔽🔽

plt.figure(figsize=(14,5))
plt.plot(df['Global_active_power'], label='Power Consumption')

plt.scatter(
    df.index[df['anomaly'] == 1],
    df['Global_active_power'][df['anomaly'] == 1],
    label='Anomaly'
)

plt.title("Energy Anomaly Detection using Isolation Forest")
plt.xlabel("Time Index")
plt.ylabel("Global Active Power")
plt.legend()
plt.show()
# 🔼🔼🔼 END OF VISUALIZATION CODE 🔼🔼🔼