# ⚡ WattBuddy - Smart Energy Management System

A comprehensive IoT-based smart electricity meter solution with real-time monitoring, anomaly detection, and predictive billing. Control your home's energy consumption directly from your phone.

## 🎯 Features

### Real-Time Monitoring
- **Live Power Tracking**: View instantaneous power consumption (W), voltage (V), and current (A)
- **Live Data Updates**: Socket.io broadcasts data every 5 seconds to the Flutter app
- **Interactive Dashboard**: Dark-themed professional UI with real-time metrics

### Smart Anomaly Detection
- **Power Spike Detection**: Automatically detects abnormal power usage (>2× baseline)
- **Socket Identification**: Identifies which socket/relay is causing the spike
- **Interactive Alerts**: Pop-up dialogs on your phone with actionable buttons
- **Remote Control**: Turn off problematic sockets directly from the app

### Billing & Prediction
- **Accurate Consumption Tracking**: Uses energy delta (MAX-MIN) instead of sums
- **Monthly Bill Prediction**: Forecasts bill based on current usage trends
- **Bill History**: View current month vs. last month consumption
- **Daily Breakdown**: Bar chart showing daily energy usage patterns
- **Slab-Based Billing**: Supports tiered electricity rates

### Hardware Integration
- **ESP32 Microcontroller**: Energy sensor via ACS712 current sensor
- **Dual Smart Relays**: Independent control of two power sockets
- **Cumulative Energy Tracking**: Persistent energy meter readings
- **Hardware Provisioning**: Automatic device-user linking on login

### Data Optimization
- **Smart Database Writes**: Only writes to DB when:
  - 60 seconds have elapsed, OR
  - Energy changes by ≥0.001 kWh
- **Reduces storage**: From ~17K rows/day to ~1.4K rows/day
- **Always-on cache**: Real-time data cached in memory for instant updates

### Automated Management
- **Monthly Reset**: Cron job automatically resets billing data on 1st of month
- **Historical Analytics**: Tracks average power consumption patterns
- **Predictive Alerts**: Warns when usage exceeds thresholds

## 📦 Tech Stack

### Frontend
- **Flutter** - Cross-platform mobile app (Android, iOS, Web)
- **Socket.io Client** - Real-time data streaming
- **FL Chart** - Professional bar/line charts
- **Shared Preferences** - Local user session storage

### Backend
- **Node.js + Express** - REST API server (Port 4000)
- **PostgreSQL 13+** - Time-series energy data storage
- **Socket.io** - WebSocket for real-time broadcasts
- **node-cron** - Scheduled tasks (monthly resets)

### Hardware
- **ESP32 DevKit** - Primary microcontroller
- **ACS712-5A** - 5A current sensor (0-5V output)
- **2× 5V Relay Modules** - Smart socket control
- **Power Supply**: USB or battery powered

## 🚀 Quick Start

### Prerequisites
```bash
# Flutter
flutter --version  # 3.0+

# Node.js
node --version    # 18+
npm --version     # 9+

# PostgreSQL
psql --version    # 13+

# Git
git clone https://github.com/Albi-n/wattbuddy.git
cd wattbuddy
```

### Backend Setup

```bash
cd wattbuddy-server
npm install

# Create .env file
cat > .env << EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=wattbuddy_db
DB_USER=postgres
DB_PASSWORD=your_password
PORT=4000
EOF

# Initialize database
npm run migrate

# Start server
npm start
# Server running at http://0.0.0.0:4000
```

### Flutter App Setup

```bash
# Install dependencies
flutter pub get

# Update API endpoint in lib/services/api_service.dart
# Change: baseUrl = 'http://your-server-ip:4000'

# Run on device/emulator
flutter run -d windows    # Windows
flutter run -d chrome     # Web browser
flutter run -d android    # Android device
```

### ESP32 Firmware

1. Upload ESP32 sketch to your microcontroller
2. Configure WiFi SSID and password in sketch
3. Set server IP address: `http://192.168.X.X:4000/api/esp32/data`
4. Device will auto-provision on user login

## 📊 API Endpoints

### Energy Monitoring
- `POST /api/esp32/data` - Receive sensor readings from ESP32
- `GET /api/usage/summary/:userId` - Get monthly summary with anomaly detection
- `GET /api/usage/daily-history/:userId` - Daily consumption for bar chart
- `GET /esp32/latest` - Get latest sensor reading from cache

### Billing
- `GET /api/billing/current/:userId` - Fetch calculated bill from SQL view
- `GET /api/power-limit/:userId` - Get user's power limit settings

### Real-Time Control
- `POST /api/relay/relay1/off` - Turn off Socket 1
- `POST /api/relay/relay2/off` - Turn off Socket 2
- `POST /api/relay/both/off` - Turn off both sockets

### Notifications
- `POST /api/notifications/log-anomaly` - Log anomaly event
- `POST /api/notifications/log-bill-prediction` - Log billing alert

## 🔌 Hardware Wiring

### ESP32 Pinout
```
ESP32 Pin    ->    Sensor
GPIO 36     ->     ACS712 OUT (A0 - ADC)
GPIO 25     ->     Relay 1 Control
GPIO 26     ->     Relay 2 Control
GND         ->     ACS712 GND
3.3V        ->     ACS712 VCC
```

## 🧪 Testing

### Test Anomaly Detection
1. Login to app
2. Open "Bill Predictor" screen
3. Plug high-power device into Socket 1 (>150W)
4. Wait for alert dialog to appear
5. Tap "TURN OFF SWITCH" to trigger relay control

### Monitor Backend Logs
```bash
cd wattbuddy-server
npm start

# Expected output:
# 📊 [ESP32 DB Save] V: 230V | I: 5.2A | P: 1200W
# 🚨 [ANOMALY DETECTED] Power: 1200W | Source: Socket 1
# ⚫ [RELAY 1 OFF] Command sent
```

## 📈 Data Flow

```
ESP32 Sensor Data → Node.js Server → Flask Cache & DB → Flutter App
                   ↓
                Anomaly Detection → Socket.io Alert → Phone Pop-up
                   ↓
                Relay Control Command
```

## 🔐 Security Notes

- Use HTTPS in production
- Store API credentials securely
- Implement user authentication before relay control
- Use environment variables for sensitive data
- Enable database encryption for energy readings

## 📝 File Structure

```
wattbuddy/
├── lib/                     # Flutter app
│   ├── screens/             # UI screens
│   ├── services/            # API & notification services
│   └── main.dart            # App entry point
├── wattbuddy-server/        # Node.js backend
│   ├── controllers/         # Request handlers
│   ├── routes/              # API endpoints
│   └── server.js            # Express server
└── README.md                # This file
```

## 🐛 Troubleshooting

### ESP32 Not Connecting
- Check WiFi credentials and server IP
- Ensure same network as backend
- Monitor serial output

### No Data in App
- Verify server running: `curl http://localhost:4000`
- Check user_id matches
- Review server logs

### Anomaly Not Triggering
- Verify power > 150W (baseline 75W)
- Check relay GPIO connections
- Review logs for `[ANOMALY DETECTED]`

## 📄 License

MIT License - See LICENSE file for details

## 👨‍💼 Author

**Albin** - IoT & Smart Systems Developer  
GitHub: [@Albi-n](https://github.com/Albi-n)

---

**Status**: Production Ready ✅  
**Last Updated**: January 2026