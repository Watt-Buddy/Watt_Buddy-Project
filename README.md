# WattBuddy — Smart Energy Management System

WattBuddy is an IoT-based smart electricity monitoring system. An ESP32 hardware sensor measures real-time power, voltage, and current, then POSTs data to a Node.js backend. A Flutter mobile app connects via Socket.io to show live readings, fire anomaly alerts, predict bills, and remotely control power sockets.

---

## Table of Contents

1. [Features](#features)
2. [Tech Stack](#tech-stack)
3. [Prerequisites](#prerequisites)
4. [Project Structure](#project-structure)
5. [Database Setup](#database-setup)
6. [Backend Setup](#backend-setup)
7. [Flutter App Setup](#flutter-app-setup)
8. [ESP32 Firmware](#esp32-firmware)
9. [Running the Project](#running-the-project)
10. [API Reference](#api-reference)
11. [Environment Variables](#environment-variables)
12. [Troubleshooting](#troubleshooting)

---

## Features

- **Real-Time Monitoring** — Live voltage, current, and power readings streamed to the app every few seconds via Socket.io
- **Anomaly Detection** — Statistical baseline (mean + 2× stddev) and 30-day pattern analysis detect abnormal power draws; alerts show the offending socket
- **Remote Relay Control** — Turn Socket 1 or Socket 2 on/off directly from the app; commands are forwarded to the ESP32
- **Smart Socket Attribution** — Learns per-socket power signatures from relay toggle events; identifies which socket is responsible for a spike
- **Predictive Billing** — Extrapolates current-month usage to forecast the end-of-month bill using tiered tariff rates
- **Bill History** — Monthly bill snapshots stored per user; view last 12 months
- **Energy Goals & Rewards** — Daily/monthly kWh limits with carry-forward logic; point-based reward tiers for meeting goals
- **Push Notifications** — FCM-based mobile push alerts for anomalies (requires `serviceAccountKey.json`)
- **Cron Jobs** — Automated midnight daily aggregation and 1st-of-month billing snapshots

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter 3.x (Android, Windows, Web) |
| Real-Time | Socket.io (server + `socket_io_client` Flutter package) |
| Backend | Node.js 18+ / Express 5 |
| Database | PostgreSQL 17 |
| Hardware | ESP32 DevKit + ACS712 current sensor + 2× relay modules |
| Charts | fl_chart |
| Local Notifications | flutter_local_notifications |
| Scheduling | node-cron |

---

## Prerequisites

Install the following before starting:

| Tool | Minimum Version |
|---|---|
| Node.js | 18 |
| npm | 9 |
| PostgreSQL | 13 (17 recommended) |
| Flutter SDK | 3.0 |
| Arduino IDE | 2.x (for ESP32 firmware upload only) |

Verify your installs:

```bash
node --version
npm --version
psql --version
flutter --version
```

---

## Project Structure

```
watt_buddy/
│
├── lib/                              # Flutter source
│   ├── main.dart
│   ├── config/
│   │   └── network_config.dart       # ESP32 IP constant
│   ├── screens/                      # UI screens
│   ├── services/                     # API, Socket.io, notifications
│   ├── utils/
│   └── widgets/
│
├── wattbuddy-server/                 # Node.js backend
│   ├── server.js                     # Main entry point
│   ├── .env                          # Environment config (not committed)
│   ├── db.js                         # PostgreSQL connection pool
│   ├── init.sql                      # Core schema (run first)
│   ├── db_updates.sql                # Schema additions
│   ├── db_updates_goal_reward_module.sql
│   ├── monthly_snapshot_migration.sql
│   ├── add_fcm_columns.sql
│   ├── initDb.js                     # Node-based DB initialiser (alternative)
│   ├── controllers/
│   ├── models/
│   ├── routes/
│   └── services/
│
├── wattbudyy-ml/                     # Python ML scripts (optional)
├── assets/images/                    # App image assets
├── ESP32_UPDATED_FIRMWARE.ino        # Arduino sketch for ESP32
└── pubspec.yaml                      # Flutter package manifest
```

---

## Database Setup

### 1. Create the database

Open a `psql` shell and run:

```sql
CREATE DATABASE wattbuddy;
```

### 2. Run schema migrations in order

Execute each SQL file against the `wattbuddy` database:

```bash
psql -U postgres -d wattbuddy -f wattbuddy-server/init.sql
psql -U postgres -d wattbuddy -f wattbuddy-server/db_updates.sql
psql -U postgres -d wattbuddy -f wattbuddy-server/db_updates_goal_reward_module.sql
psql -U postgres -d wattbuddy -f wattbuddy-server/monthly_snapshot_migration.sql
psql -U postgres -d wattbuddy -f wattbuddy-server/add_fcm_columns.sql
```

> The server also auto-creates `UserStats`, `relay_toggle_events`, `user_power_patterns`, and `alert_dismissals` tables on first startup.

### Key tables

| Table | Purpose |
|---|---|
| `users` | Registered user accounts |
| `"EnergyReadings"` | Raw sensor data (voltage, current, power, energy, relay states) |
| `energy_readings` | Alternate readings table used by the graph service |
| `daily_usage` | Aggregated daily kWh per user |
| `monthly_limits` | Per-user monthly kWh limits |
| `monthly_usage` | Monthly usage tracking with carry-forward |
| `monthly_energy_snapshots` | Start-of-month energy readings for accurate billing |
| `anomaly_alerts` | Logged anomaly events |
| `notifications` | In-app notification log |
| `user_settings` | Per-user alert thresholds |
| `relay_toggle_events` | Relay on/off events with power deltas (used for socket learning) |
| `user_power_patterns` | Cached 30-day hourly/weekly consumption patterns |
| `alert_dismissals` | Dismissed alerts with 2-minute re-alert scheduling |
| `goals` | User-defined energy goals |
| `user_rewards` | Points, tiers, streaks, and achievements |
| `"UserStats"` | Cumulative total energy per user |

---

## Backend Setup

### 1. Install dependencies

```bash
cd wattbuddy-server
npm install
```

### 2. Create the `.env` file

Create `wattbuddy-server/.env`:

```env
PORT=4000
DATABASE_URL=postgres://postgres:<your_password>@localhost:5432/wattbuddy
JWT_SECRET=<any_random_string>
```

Replace `<your_password>` with your PostgreSQL password.

### 3. Set the ESP32 IP address

Open `wattbuddy-server/server.js` and update the constant near the top:

```js
const ESP32_IP = '192.168.X.X';   // Set to your ESP32's IP on your network
```

### 4. (Optional) Enable Firebase Push Notifications

1. Go to Firebase Console → Project Settings → Service Accounts
2. Click **Generate new private key** and download the JSON file
3. Save it as `wattbuddy-server/serviceAccountKey.json`

Without this file the server starts normally but FCM push notifications are silently disabled.

### 5. Start the server

```bash
npm start
```

Successful startup output:

```
✅ Database client connected
✅ Pattern analysis schema initialized
✅ Ensured table "UserStats" exists
🚀 ================================
   WattBuddy Server: ONLINE
================================
🌐 Listening at: http://0.0.0.0:4000
```

For development with auto-restart:

```bash
npm run dev
```

---

## Flutter App Setup

### 1. Install Flutter dependencies

From the project root:

```bash
flutter pub get
```

### 2. Configure the server URL

The app resolves the backend URL automatically:

| Platform | Default URL |
|---|---|
| Windows / Desktop | `http://localhost:4000/api` |
| Android Emulator | `http://10.0.2.2:4000/api` |
| Real Android Phone | Must be passed via `--dart-define` (see below) |

For a real Android device, pass your PC's LAN IP at run time:

```bash
flutter run -d android --dart-define=API_BASE_URL=http://192.168.X.X:4000/api
```

### 3. Update the ESP32 IP in Dart

Open `lib/config/network_config.dart` and set:

```dart
static const String ESP32_IP = '192.168.X.X';
```

Also update the `espIp` constant inside `getESP32Sensors()` in `lib/services/api_service.dart` to the same IP.

### 4. Run the app

```bash
flutter run -d windows    # Desktop (Windows)
flutter run -d chrome     # Web browser
flutter run -d android    # Android emulator or device
```

---

## ESP32 Firmware

The Arduino sketch is `ESP32_UPDATED_FIRMWARE.ino`.

### Hardware connections

| ESP32 Pin | Connected To |
|---|---|
| GPIO 36 (ADC1_CH0) | ACS712 analog output |
| GPIO 25 | Relay module 1 control |
| GPIO 26 | Relay module 2 control |
| 3.3V | ACS712 VCC |
| GND | ACS712 GND, Relay GND |

### Before uploading

Edit the sketch and fill in your values:

```cpp
const char* ssid      = "YourWiFiSSID";
const char* password  = "YourWiFiPassword";
const char* serverUrl = "http://192.168.X.X:4000/api/esp32/data";
```

`serverUrl` should point to the machine running the Node.js server.

### Upload steps

1. Open `ESP32_UPDATED_FIRMWARE.ino` in Arduino IDE 2.x
2. Install ESP32 board support: **Boards Manager** → search `esp32` → install by Espressif Systems
3. **Tools → Board → ESP32 Dev Module**
4. Select the correct COM port
5. Click **Upload**
6. Open **Serial Monitor** at 115200 baud — the ESP32 prints its assigned IP address on boot

Use that IP in `server.js` (`ESP32_IP`) and `lib/config/network_config.dart` (`ESP32_IP`).

### Data format POSTed by ESP32

```json
{
  "voltage": 230.5,
  "current": 2.3,
  "power": 530.15,
  "energy": 0.147,
  "relay1": 1,
  "relay2": 0,
  "dominantRelay": 1,
  "dominantPower": 530.15,
  "userId": "11"
}
```

---

## Running the Project

Start all components in order:

**Step 1 — Start PostgreSQL**

```powershell
# Windows PowerShell
Get-Service postgresql-x64-17 | Start-Service
```

**Step 2 — Start the backend server**

```bash
cd wattbuddy-server
npm start
```

**Step 3 — Launch the Flutter app**

```bash
# From project root
flutter run -d windows
```

**Step 4 — Power on the ESP32**

The ESP32 connects to WiFi and POSTs sensor data to the server automatically.

---

## API Reference

### ESP32 Ingestion

| Method | Path | Description |
|---|---|---|
| POST | `/api/esp32/data` | Receive sensor readings from ESP32 |
| GET | `/esp32/latest` | Get latest cached reading |

### Usage & Analytics

| Method | Path | Description |
|---|---|---|
| GET | `/api/usage/summary/:userId` | Monthly summary with anomaly fields |
| GET | `/api/usage/daily-history/:userId` | Daily kWh array for current month |
| GET | `/api/usage/baseline/:userId` | Statistical baseline (mean, stddev, threshold) |
| POST | `/api/usage/backfill/:userId` | Backfill daily aggregates from raw readings |
| POST | `/api/usage/aggregate-today/:userId` | Trigger today's aggregation manually |

### Billing

| Method | Path | Description |
|---|---|---|
| GET | `/api/billing/current/:userId` | Current month bill |
| GET | `/api/billing/history/:userId` | Past 12 months of bills |
| GET | `/api/billing/calculate/:userId` | Detailed bill with breakdown |
| GET | `/api/billing/predict/:userId` | Projected end-of-month bill |
| GET | `/api/billing/detailed-history/:userId` | Full breakdown per month (`?monthsBack=6`) |
| GET | `/api/billing/summary/:userId` | Current + projection + last-month comparison |

### Relay Control

| Method | Path | Description |
|---|---|---|
| GET | `/api/relay/relay1/on` | Turn Socket 1 ON |
| GET | `/api/relay/relay1/off` | Turn Socket 1 OFF |
| GET | `/api/relay/relay2/on` | Turn Socket 2 ON |
| GET | `/api/relay/relay2/off` | Turn Socket 2 OFF |
| GET | `/api/relay/status` | Current relay states from in-memory cache |
| GET | `/api/relay/signatures/:userId` | Learned per-socket power signatures |

### Anomaly & Alerts

| Method | Path | Description |
|---|---|---|
| POST | `/api/alerts/dismiss/:alertId` | Dismiss an alert (re-alerts in 2 min if power still high) |
| POST | `/api/pattern/analyze/:userId` | Manually trigger 30-day pattern analysis |

### Authentication

| Method | Path | Description |
|---|---|---|
| POST | `/api/auth/register` | Register a new user |
| POST | `/api/auth/login` | Login — returns JWT token |

### Notifications

| Method | Path | Description |
|---|---|---|
| POST | `/api/notifications/register-fcm` | Register or update FCM token |
| POST | `/api/notifications/register-mobile` | Register mobile number |
| GET | `/api/notifications/push-history/:userId` | FCM notification history |
| POST | `/api/notifications/test-push` | Send a test push notification |

### Goals & Rewards

| Method | Path | Description |
|---|---|---|
| GET | `/api/goals/:userId` | Get user goals |
| POST | `/api/goals/:userId` | Create or update goals |
| GET | `/api/rewards/:userId` | Reward profile (points, tier, streak) |

### Power Limit

| Method | Path | Description |
|---|---|---|
| POST | `/api/power-limit/check` | Check if usage exceeds daily limit |
| GET | `/api/power-limit/:userId` | Get power limit settings |

### Graph

| Method | Path | Description |
|---|---|---|
| GET | `/api/graph/live/:userId` | Last N minutes of power readings (`?minutes=60`) |

### ML Predictions

| Method | Path | Description |
|---|---|---|
| GET | `/api/ml-predict/next-hour/:userId` | Predict next-hour power consumption |

### Debug (Development Only)

| Method | Path | Description |
|---|---|---|
| GET | `/api/debug/trigger-anomaly` | Emit a test anomaly alert via Socket.io |
| GET | `/api/debug/recent-energy` | View last 20 raw energy rows |

---

## Environment Variables

All variables go in `wattbuddy-server/.env`:

| Variable | Example Value | Description |
|---|---|---|
| `PORT` | `4000` | Port the Express server listens on |
| `DATABASE_URL` | `postgres://postgres:pass@localhost:5432/wattbuddy` | Full PostgreSQL connection string |
| `JWT_SECRET` | `mysecretkey` | Secret for signing JWT tokens |

---

## Troubleshooting

**Server fails to connect to PostgreSQL**  
Verify the password and database name in `DATABASE_URL`. Test with:
```bash
psql "postgres://postgres:<password>@localhost:5432/wattbuddy"
```

**Flutter app shows no live data**  
- Confirm the server is running on port 4000  
- For a real Android phone, pass `--dart-define=API_BASE_URL=http://<LAN_IP>:4000/api`  
- Ensure the phone and server are on the same network

**Relay commands time out**  
- Confirm `ESP32_IP` in `server.js` matches the ESP32's actual IP (shown in Serial Monitor)  
- Both the server PC and ESP32 must be on the same network

**Flutter Windows build fails — LNK1168 error**  
A previous app instance is locking the `.exe`. Kill it first:
```powershell
Get-Process | Where-Object { $_.ProcessName -like "*watt_buddy*" } | Stop-Process -Force
flutter run -d windows
```

**Anomaly alerts not triggering**  
The system needs at least 3 days of data before baseline detection activates. During the initial grace period, alerts are suppressed. Check baseline status:
```
GET /api/usage/baseline/:userId
```

**Socket attribution shows "Unknown Socket"**  
The attribution engine needs relay toggle training data. To build it:
1. Turn **only Socket 1** on for ~15 seconds, then off — repeat 3 times
2. Turn **only Socket 2** on for ~15 seconds, then off — repeat 3 times

This populates `relay_toggle_events` with enough samples for the system to learn each socket's power signature.
