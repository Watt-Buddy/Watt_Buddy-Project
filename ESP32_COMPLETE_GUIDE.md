# ESP32 Energy Monitor - Complete Corrected Code Guide

## Issues Found in Original Code

### ❌ **Problems:**
1. **No backend integration** - Readings only printed to Serial, not stored in database
2. **No user tracking** - No way to know which user is logged in
3. **No relay control endpoints** - Relay can't be controlled remotely
4. **No energy tracking** - No kWh calculations
5. **No anomaly alerts** - Safety thresholds not implemented
6. **No persistent storage** - Data lost on reboot
7. **Missing WiFi error handling** - Crashes if WiFi unavailable
8. **No time synchronization** - Timestamps meaningless without NTP sync

---

## ✅ **Fixes Applied**

### 1. **User Tracking System**
```cpp
String LOGGED_IN_USER = "";  // Set by /user/set endpoint

// When user logs in from Flutter app:
// POST /user/set?userId=USER_123

// Now all sensor data includes userId for the logged-in user
```

### 2. **Backend Integration**
```cpp
// Sensor data is automatically sent to backend every 10 seconds:
// POST http://10.168.130.214:4000/api/sensor-data/log

{
  "userId": "USER_123",
  "deviceId": "ESP32_DEVICE_001",
  "voltage": 230.45,
  "current": 2.34,
  "power": 540.25,
  "relay": true,
  "dailyEnergy": 12.45,
  "monthlyEnergy": 325.60,
  "timestamp": 1705775400
}
```

### 3. **Energy Tracking (kWh Calculation)**
```cpp
// Real-time energy calculation from power readings:
float energyKwh = powerW * timeDiffMs / 3600000;

// Tracks:
// - totalEnergy: Cumulative since boot
// - dailyEnergy: Since midnight
// - monthlyEnergy: Since start of month

// Saved to SPIFFS for persistence after reboot
```

### 4. **Relay Control Endpoints**
```
POST /relay/on       → Turns relay ON
POST /relay/off      → Turns relay OFF
GET  /relay/status   → Returns current relay state + sensor readings
```

### 5. **Safety Features**
```cpp
// Thresholds:
const float OVERVOLTAGE_THRESHOLD = 250.0;      // V
const float UNDERVOLTAGE_THRESHOLD = 180.0;     // V
const float OVERCURRENT_THRESHOLD = 5.0;        // A
const float OVERPOWER_THRESHOLD = 2500.0;       // W

// On anomaly: Relay automatically shuts down + logs to backend
emergencyShutdown() → POST /api/anomalies/log
```

### 6. **Persistent Storage (SPIFFS)**
```cpp
// Energy data saved every 5 minutes
// Survives power loss and reboot
// File: /energy.json on ESP32 flash memory
```

### 7. **NTP Time Synchronization**
```cpp
// Syncs with NTP servers on startup (UTC+5:30 for IST)
// Provides accurate timestamps for database logging
```

---

## 📊 **New Web Server Endpoints**

### **Sensor Reading**
```
GET /sensors
Response: {
  "voltage": 230.45,
  "current": 2.34,
  "power": 540.25,
  "relay": true,
  "totalEnergy": 150.32,
  "dailyEnergy": 12.45,
  "monthlyEnergy": 325.60,
  "user": "USER_123",
  "timestamp": 1705775400
}
```

### **Relay Control**
```
POST /relay/on
POST /relay/off
Response: {"success": true, "relay": "ON"}

GET /relay/status
Response: {
  "relay": true,
  "voltage": 230.45,
  "current": 2.34,
  "power": 540.25,
  "user": "USER_123"
}
```

### **User Management**
```
POST /user/set?userId=USER_123
Response: {"success": true, "user": "USER_123"}
```

### **Energy Data**
```
GET /energy
Response: {
  "totalEnergy": 150.32,
  "dailyEnergy": 12.45,
  "monthlyEnergy": 325.60
}

POST /energy/reset-daily
POST /energy/reset-monthly
```

---

## 🔧 **Hardware Setup Checklist**

- [ ] **ACS712-5A** (Current Sensor) → GPIO 35 (ADC1)
- [ ] **ZMPT101B** (Voltage Sensor) → GPIO 34 (ADC1)
- [ ] **Relay Module** → GPIO 18
- [ ] **Status LED** → GPIO 2
- [ ] **GND** - All sensors connected to common ground

---

## 📱 **Flutter App Integration**

### **1. Set logged-in user when user logs in:**
```dart
// In login_register.dart, after successful login:
final response = await http.post(
  Uri.parse('http://10.168.130.214:80/user/set?userId=$userId'),
);
```

### **2. Display real-time readings on dashboard:**
```dart
// In dashboard_screen.dart:
final sensorData = await http.get(
  Uri.parse('http://10.168.130.214:80/sensors'),
);
```

### **3. Control relay from devices screen:**
```dart
// In devices_screen.dart:
await http.post(Uri.parse('http://10.168.130.214:80/relay/on'));
await http.post(Uri.parse('http://10.168.130.214:80/relay/off'));
```

### **4. Display energy consumption on bill predictor:**
```dart
final energyData = await http.get(
  Uri.parse('http://10.168.130.214:80/energy'),
);
```

---

## 🔌 **Installation Steps**

### **Step 1: Upload to ESP32**
1. Open Arduino IDE
2. Install ESP32 board: `https://dl.espressif.com/dl/package_esp32_index.json`
3. Select **Tools → Board → ESP32 Dev Module**
4. Paste the corrected code
5. Click **Upload**

### **Step 2: Configure WiFi**
Edit these lines in the code:
```cpp
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";
const char* BACKEND_URL = "http://10.168.130.214:4000";
```

### **Step 3: Monitor Serial Output**
```
✅ Calibrating ACS712...
✅ WiFi Connected
⏰ Syncing time with NTP...
✅ Time synced: Mon Jan 20 14:30:45 2025
✅ ESP32 Energy Monitor Started
```

### **Step 4: Set Logged-In User**
When user logs in from Flutter app, send:
```
POST http://ESP32_IP:80/user/set?userId=USER_ID
```

---

## 📊 **Backend Database Schema (MongoDB)**

```javascript
// sensorLogs collection
{
  userId: "USER_123",
  deviceId: "ESP32_DEVICE_001",
  voltage: 230.45,
  current: 2.34,
  power: 540.25,
  relay: true,
  dailyEnergy: 12.45,
  monthlyEnergy: 325.60,
  timestamp: ISODate("2025-01-20T14:30:45Z"),
  createdAt: ISODate("2025-01-20T14:30:45Z")
}

// anomalies collection
{
  userId: "USER_123",
  deviceId: "ESP32_DEVICE_001",
  anomalyType: "Overvoltage",
  voltage: 260,
  current: 2.34,
  power: 540,
  severity: 85,
  autoShutdown: true,
  timestamp: ISODate("2025-01-20T14:30:45Z"),
  createdAt: ISODate("2025-01-20T14:30:45Z")
}

// relayLogs collection
{
  userId: "USER_123",
  deviceId: "ESP32_DEVICE_001",
  relayNumber: 1,
  state: "ON",
  timestamp: ISODate("2025-01-20T14:30:45Z"),
  createdAt: ISODate("2025-01-20T14:30:45Z")
}
```

---

## 🚀 **Testing**

### **Test 1: Check sensor readings**
```bash
curl http://10.168.130.214:80/sensors
```
Response:
```json
{
  "voltage": 230.45,
  "current": 2.34,
  "power": 540.25,
  "relay": true,
  "dailyEnergy": 12.45,
  "monthlyEnergy": 325.60,
  "user": "",
  "timestamp": 1705775400
}
```

### **Test 2: Set user and control relay**
```bash
# Set user
curl http://10.168.130.214:80/user/set?userId=USER_123

# Turn relay ON
curl -X POST http://10.168.130.214:80/relay/on

# Check status
curl http://10.168.130.214:80/relay/status
```

### **Test 3: Monitor backend logs**
```bash
# Watch the server logs
tail -f /var/log/wattbuddy-server.log
```
You should see:
```
📊 Sensor Data from ESP32_DEVICE_001 [User: USER_123]
   Voltage: 230.45V | Current: 2.34A | Power: 540.25W
   Daily Energy: 12.45 kWh | Monthly: 325.60 kWh
```

---

## 🐛 **Troubleshooting**

| Issue | Solution |
|-------|----------|
| WiFi not connecting | Check SSID/password in code, ensure 2.4GHz network |
| Sensor readings 0 | Verify GPIO connections, check ADC attenuation |
| Backend not receiving data | Check backend URL, ensure server is running, check firewall |
| User not being set | Send POST /user/set?userId=X before reading sensors |
| Relay not toggling | Check GPIO 18 connection, verify power supply to relay module |
| Energy stuck at 0 | Check system time (NTP sync), power must be > 0W |

---

## 📝 **Summary**

✅ **Original Code Issues: FIXED**
- ✅ Backend integration added
- ✅ User tracking implemented
- ✅ Relay control added
- ✅ Energy tracking (kWh) implemented
- ✅ Safety thresholds with auto-shutdown
- ✅ SPIFFS persistence
- ✅ NTP time sync
- ✅ Proper error handling

✅ **Readings now sent to:**
- Backend database (every ~10 seconds)
- Logged-in user's dashboard (real-time via /sensors endpoint)
- SPIFFS flash (every 5 minutes)

---

**Ready to upload! 🚀**
