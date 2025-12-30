import pandas as pd
import joblib

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import KNeighborsClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LinearRegression

from sklearn.metrics import accuracy_score, classification_report, mean_absolute_error

# -----------------------------
# 1. LOAD DATASET
# -----------------------------
DATA_PATH = "../data/kerala_energy_1year.csv"
df = pd.read_csv(DATA_PATH)

# -----------------------------
# COMMON FEATURES
# -----------------------------
FEATURES = [
    "Global_active_power",
    "Voltage",
    "Global_intensity",
    "Sub_metering_1",
    "Sub_metering_2",
    "Sub_metering_3",
    "Sub_metering_4"
]

TARGET = "Anomaly_flag"

X = df[FEATURES]
y = df[TARGET]

# ============================================================
# 2. KNN CLASSIFICATION (BASELINE)
# ============================================================
print("\n🔹 Training KNN Classifier")

# Scaling required for KNN
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

X_train, X_test, y_train, y_test = train_test_split(
    X_scaled, y, test_size=0.2, random_state=42
)

knn = KNeighborsClassifier(n_neighbors=5)
knn.fit(X_train, y_train)

y_pred_knn = knn.predict(X_test)

print("KNN Accuracy:", accuracy_score(y_test, y_pred_knn))

# Save model
joblib.dump(knn, "../models/knn_model.pkl")
joblib.dump(scaler, "../models/knn_scaler.pkl")

# ============================================================
# 3. RANDOM FOREST (ANOMALY DETECTION - MAIN MODEL)
# ============================================================
print("\n🔹 Training Random Forest Anomaly Detector")

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

rf = RandomForestClassifier(
    n_estimators=100,
    random_state=42
)

rf.fit(X_train, y_train)
y_pred_rf = rf.predict(X_test)

print("\nRandom Forest Classification Report:")
print(classification_report(y_test, y_pred_rf))

# Feature importance (important for viva)
print("Feature Importance:")
for name, importance in zip(FEATURES, rf.feature_importances_):
    print(f"{name}: {importance:.3f}")

# Save model
joblib.dump(rf, "../models/rf_anomaly_model.pkl")

# ============================================================
# 4. LINEAR REGRESSION (FORECASTING)
# ============================================================
print("\n🔹 Training Linear Regression Forecasting Model")

# Create next-step prediction target
df["Next_power"] = df["Global_active_power"].shift(-1)
df.dropna(inplace=True)

X_forecast = df[
    [
        "Global_active_power",
        "Sub_metering_1",
        "Sub_metering_2",
        "Sub_metering_3",
        "Sub_metering_4"
    ]
]

y_forecast = df["Next_power"]

X_train, X_test, y_train, y_test = train_test_split(
    X_forecast, y_forecast, test_size=0.2, random_state=42
)

lr = LinearRegression()
lr.fit(X_train, y_train)

y_pred_lr = lr.predict(X_test)

print("Forecasting MAE:", mean_absolute_error(y_test, y_pred_lr))

# Save model
joblib.dump(lr, "../models/linear_forecast_model.pkl")

print("\n✅ ALL MODELS TRAINED AND SAVED SUCCESSFULLY")
