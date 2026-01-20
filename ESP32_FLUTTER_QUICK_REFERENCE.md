# ESP32 & Flutter Integration - Quick Reference

## 📱 Flutter Screens Added

### 1. **RelayControlScreen** 
Location: `lib/screens/relay_control_screen.dart`

**Features:**
- Toggle relay on/off with animated button
- Real-time sensor readings (Voltage, Current, Power, Frequency)
- Visual status indicator (Green=ON, Grey=OFF)
- Safety information banner
- Auto-refresh sensor data

**Usage:**
```dart
import 'lib/screens/relay_control_screen.dart';

// Add to navigation
RelayControlScreen()
```

**What it does:**
- Controls power supply via relay module
- Shows live sensor values from ACS712 & ZMPT101B
- Safe on/off switching with visual feedback

---

### 2. **ElectricityPredictionScreen**
Location: `lib/screens/electricity_prediction_screen.dart`

**Features:**
- Shows next hour power consumption prediction
- Shows tomorrow's daily energy prediction
- Displays detected anomalies with details
- Energy saving recommendations
- Anomaly alert notifications
- Auto-refresh with refresh button

**Usage:**
```dart
import 'lib/screens/electricity_prediction_screen.dart';

// Add to navigation
ElectricityPredictionScreen()
```

**What it does:**
- Predicts future energy consumption using ML
- Detects anomalies automatically
- Shows notifications when anomalies detected
- Provides energy-saving tips

---

## 🔌 Services Added

### 1. **AnomalyNotificationService**
Location: `lib/services/anomaly_notification_service.dart`

**Methods:**
```dart
// Send anomaly alert
sendAnomalyAlert({
  required String title,
  required String body,
  required double voltage,
  required double current,
  required double power,
  required String anomalyType,
})

// Send prediction warning
sendPredictionWarning({
  required String title,
  required String body,
  required String predictedIssue,
  String? recommendation,
})

// Send daily summary
sendDailySummary({
  required String dailyEnergy,
  required String peakPower,
  required String averagePower,
  required int anomalyCount,
})

// Send relay control notification
sendRelayControlNotification({
  required bool isOn,
  required String reason,
})
```

---

### 2. **RelayControlService**
Location: `lib/services/relay_control_service.dart`

**Methods:**
```dart
// Control relay
controlRelay({
  required String userId,
  required bool turnOn,
  String reason = 'User requested',
})

// Get relay status
getRelayStatus(String userId)

// Auto-disable on anomaly
autoDisableOnAnomaly({
  required String userId,
  required String anomalyType,
})

// Toggle relay
toggleRelay(String userId)

// Set schedule
setRelaySchedule({
  required String userId,
  required DateTime startTime,
  required DateTime endTime,
})

// Get relay history
getRelayHistory({
  required String userId,
  int limit = 50,
})

// Get relay health
getRelayHealth(String userId)
```

---

## 🖥️ ESP32 Endpoints

### Local HTTP Endpoints

```bash
# Set user ID (called from app)
GET http://esp32-ip/set-user/{userId}

# Get sensor readings
GET http://esp32-ip/sensors
Response: {
  "voltage": 230.5,
  "current": 2.34,
  "power": 540.2,
  "pf": 0.95,
  "frequency": 50.0,
  "temperature": 28.5,
  "relayState": true
}

# Relay control
GET http://esp32-ip/relay/on
GET http://esp32-ip/relay/off
GET http://esp32-ip/relay/toggle
GET http://esp32-ip/relay/status

# Health check
GET http://esp32-ip/health
Response: {
  "status": "online",
  "currentUser": 123,
  "ip": "192.168.x.x",
  "signal": -45,
  "voltage": 230.5,
  "current": 2.34,
  "relayState": true
}
```

---

## 🔧 Sensor Specifications

### ACS712 Current Sensor
- **Sensitivity (5A):** 185 mV/A
- **Zero Offset:** 2.5V
- **Output Range:** 0-5V
- **Max Current:** 5A (or 20A/30A variant)

### ZMPT101B Voltage Sensor
- **Sensitivity:** 0.00467V per unit
- **Output Range:** 0-3.3V
- **Reads:** AC voltage up to 250V
- **Accuracy:** ±2%

### Relay Module
- **Control Voltage:** 5V
- **Max Load:** 10A @ 250VAC
- **Response Time:** <5ms
- **Lifespan:** 100,000+ cycles

---

## ⚡ Anomaly Detection Logic

**Thresholds (Configurable):**
- Power > 5000W → Over-power alert
- Voltage > 250V → Over-voltage alert
- Current > 20A → Over-current alert
- Temperature > 45°C → Over-temperature alert

**Actions on Detection:**
1. Log anomaly to server
2. Send push notification
3. Auto-cut relay (for power/current)
4. Store anomaly in history

---

## 📊 Data Flow

### Reading Cycle (Every 10 seconds)
```
1. ESP32 reads sensors (ACS712, ZMPT101B)
2. Calculate power = voltage × current
3. Detect anomalies
4. Send to server
5. Server triggers ML predictions
6. App receives updates
7. Notifications sent if needed
```

### Prediction Cycle (Triggered by app)
```
1. App requests next-hour prediction
2. Server processes last 7 days of data
3. ML model predicts consumption
4. Returns prediction + confidence
5. App shows notification if anomaly detected
6. User can view details in prediction screen
```

---

## 🚀 Integration Checklist

- [ ] Upload ESP32 code to board
- [ ] Configure WiFi SSID/password
- [ ] Set server URL correctly
- [ ] Calibrate ACS712 sensitivity
- [ ] Calibrate ZMPT101B voltage
- [ ] Add Flutter screens to app
- [ ] Initialize notification service in main()
- [ ] Test relay control endpoint
- [ ] Test sensor readings
- [ ] Test anomaly detection
- [ ] Test notifications
- [ ] Set anomaly thresholds
- [ ] Test app prediction screen

---

## 🔍 Testing Commands

```bash
# Test ESP32 health
curl http://192.168.x.x/health

# Get sensor readings
curl http://192.168.x.x/sensors

# Turn relay on
curl http://192.168.x.x/relay/on

# Turn relay off
curl http://192.168.x.x/relay/off

# Set user ID
curl http://192.168.x.x/set-user/123
```

---

## 📱 App Integration Code

Add to your main navigation/bottom bar:

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: BottomNavigationBar(
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.power_settings_new),
              label: 'Relay Control', // NEW
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.trending_up),
              label: 'Predictions', // NEW
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
          onTap: (index) {
            switch(index) {
              case 0:
                // Dashboard
                break;
              case 1:
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => RelayControlScreen()),
                );
                break;
              case 2:
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ElectricityPredictionScreen()),
                );
                break;
              case 3:
                // Settings
                break;
            }
          },
        ),
      ),
    );
  }
}
```

---

## 🐛 Debugging Tips

**ESP32 Console Messages:**
- ✅ = Success
- ❌ = Error
- ⚠️ = Warning
- 📤 = Data sent
- 📥 = Data received

**Common Issues & Solutions:**

| Issue | Cause | Solution |
|-------|-------|----------|
| Current reads 0 | ADC connection | Check GPIO35 connection |
| Voltage wrong | Calibration | Adjust VOLTAGE_MULTIPLIER |
| Relay not working | Power issue | Verify 5V to relay |
| No notifications | Permissions | Enable in app settings |
| Server not responding | Network | Check same WiFi network |

---

## 📞 API Response Formats

### Anomaly Notification (Server sends to app):
```json
{
  "anomalyType": "Overcurrent",
  "voltage": 230.5,
  "current": 25.3,
  "power": 5847.65,
  "timestamp": "2024-01-19T10:30:00Z"
}
```

### Relay Status Response:
```json
{
  "success": true,
  "relayState": true,
  "reason": "User requested"
}
```

### Sensor Data Response:
```json
{
  "voltage": 230.5,
  "current": 2.34,
  "power": 540.2,
  "pf": 0.95,
  "frequency": 50.0,
  "temperature": 28.5,
  "relayState": true
}
```

---

**Version:** 1.0
**Last Updated:** January 19, 2026
**Status:** Ready for Deployment ✅
