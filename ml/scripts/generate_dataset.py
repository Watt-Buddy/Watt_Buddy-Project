import csv
import random
from datetime import datetime, timedelta

# ----------------------------
# CONFIGURATION
# ----------------------------
START_DATE = datetime(2024, 1, 1, 0, 0)
END_DATE   = datetime(2024, 12, 31, 23, 45)
INTERVAL   = timedelta(minutes=15)
VOLTAGE    = 230  # Kerala single-phase voltage

OUTPUT_FILE = "kerala_energy_1year.csv"

# ----------------------------
# HELPER FUNCTIONS
# ----------------------------

def get_season(month):
    if month in [3, 4, 5]:
        return "summer"
    elif month in [6, 7, 8, 9]:
        return "monsoon"
    else:
        return "winter"

def bedroom_usage(hour):
    if 22 <= hour or hour <= 6:
        return random.randint(120, 200)   # fan + light
    return random.randint(20, 60)

def living_usage(hour):
    if 18 <= hour <= 22:
        return random.randint(100, 200)   # TV + lights
    return random.randint(30, 70)

def kitchen_usage(hour):
    if hour in [7, 8, 12, 13, 19, 20]:
        return random.randint(800, 1500)  # cooking
    return random.randint(20, 80)

def bathroom_usage(hour):
    if 5 <= hour <= 7:
        return random.choice([0, 1000, 1500])  # geyser
    return 0

# ----------------------------
# CSV GENERATION
# ----------------------------

with open(OUTPUT_FILE, "w", newline="", encoding="utf-8") as file:
    writer = csv.writer(file)

    # Header
    writer.writerow([
        "Date", "Time",
        "Global_active_power", "Voltage", "Global_intensity",
        "Sub_metering_1", "Sub_metering_2",
        "Sub_metering_3", "Sub_metering_4",
        "Season", "Occupancy", "Anomaly_flag"
    ])

    current = START_DATE

    while current <= END_DATE:
        hour = current.hour
        season = get_season(current.month)
        occupancy = "home"

        # Room-level consumption
        bedroom  = bedroom_usage(hour)
        living   = living_usage(hour)
        kitchen  = kitchen_usage(hour)
        bathroom = bathroom_usage(hour)

        # Total power
        total_power = bedroom + living + kitchen + bathroom
        current_amp = round(total_power / VOLTAGE, 2)

        # Anomaly injection (2% chance)
        anomaly = 0
        if random.random() < 0.02:
            bathroom += 2000  # heater stuck ON
            total_power += 2000
            anomaly = 1

        writer.writerow([
            current.strftime("%d/%m/%Y"),
            current.strftime("%H:%M"),
            total_power,
            VOLTAGE,
            current_amp,
            bedroom,
            living,
            kitchen,
            bathroom,
            season,
            occupancy,
            anomaly
        ])

        current += INTERVAL

print("✅ Dataset created successfully:", OUTPUT_FILE)
