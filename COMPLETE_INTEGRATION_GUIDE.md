# Complete Integration & Testing Guide

## Files Created/Updated

### 📁 New Files Created:

1. **ESP32 Code:**
   - `esp32_energy_monitor.ino` - Main ESP32 firmware with sensors and relay control

2. **Flutter Screens:**
   - `lib/screens/relay_control_screen.dart` - Power on/off control UI
   - `lib/screens/electricity_prediction_screen.dart` - Predictions & anomaly alerts

3. **Flutter Services:**
   - `lib/services/anomaly_notification_service.dart` - Anomaly & prediction notifications
   - `lib/services/relay_control_service.dart` - Relay control operations

4. **Documentation:**
   - `SENSOR_SETUP_GUIDE.md` - Hardware setup and calibration
   - `ESP32_FLUTTER_QUICK_REFERENCE.md` - Quick API reference
   - `COMPLETE_INTEGRATION_GUIDE.md` - This file

---

## Step-by-Step Integration

### Phase 1: Hardware Setup (30 minutes)

#### 1.1 Connect Components
```
ACS712-5A:
  VCC (5V) → 5V Power
  GND → Common Ground
  OUT → ESP32 GPIO 35

ZMPT101B:
  VCC (5V) → 5V Power
  GND → Common Ground
  OUT → ESP32 GPIO 34

Relay Module:
  VCC (5V) → 5V Power
  GND → Common Ground
  IN → ESP32 GPIO 23

Power Supply:
  3.3V → ESP32
  5V → Sensors & Relay
  GND → Common Ground
```

#### 1.2 Upload ESP32 Code
```bash
# In Arduino IDE:
1. Open arduino_ide
2. Copy content from esp32_energy_monitor.ino
3. Select Board: ESP32-WROOM-32
4. Select Port: COM port where ESP32 is connected
5. Click Upload
6. Wait for "Connecting" and then "Uploaded"
```

#### 1.3 Verify Upload
```
Serial Monitor (115200 baud):
✅ SPIFFS Mounted
📡 Connecting to WiFi
✅ WiFi Connected
📡 ESP32 IP: 192.168.x.x
✅ WebServer started on port 80
```

---

### Phase 2: ESP32 Configuration (15 minutes)

#### 2.1 Update WiFi Credentials
In `esp32_energy_monitor.ino`:
```cpp
const char* ssid = "your_actual_wifi_name";
const char* password = "your_actual_password";
```

#### 2.2 Update Server URL
```cpp
const char* serverUrl = "http://your_server_ip:4000/api/esp32/data";
const char* anomalyUrl = "http://your_server_ip:4000/api/anomaly/detect";
```

#### 2.3 Calibrate Sensors
```cpp
// For your region
const float VOLTAGE_MULTIPLIER = 220.0;  // or 110.0

// For your ACS712 variant
const float ACS712_SENSITIVITY = 0.185;  // 5A
// or 0.100 for 20A
// or 0.066 for 30A
```

#### 2.4 Set Anomaly Thresholds
```cpp
float POWER_THRESHOLD = 5000.0;    // Max safe power in Watts
float VOLTAGE_THRESHOLD = 250.0;   // Max safe voltage
float CURRENT_THRESHOLD = 20.0;    // Max safe current
```

---

### Phase 3: Flutter App Integration (45 minutes)

#### 3.1 Update pubspec.yaml
Ensure these are present:
```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  shared_preferences: ^2.0.0
  flutter_local_notifications: ^14.0.0
```

Run: `flutter pub get`

#### 3.2 Update main.dart
```dart
import 'package:flutter/material.dart';
import 'lib/services/anomaly_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notifications
  await AnomalyNotificationService.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WattBuddy',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}
```

#### 3.3 Add Navigation
Add to your navigation/bottom bar:

```dart
import 'lib/screens/relay_control_screen.dart';
import 'lib/screens/electricity_prediction_screen.dart';

// In your navigation handler:
case 'relay':
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const RelayControlScreen()),
  );
  break;
case 'prediction':
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ElectricityPredictionScreen()),
  );
  break;
```

#### 3.4 Update AndroidManifest.xml
Add permissions:
```xml
<manifest ...>
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  
  <application
      android:usesCleartextTraffic="true"
      ...>
  </application>
</manifest>
```

---

### Phase 4: Testing (60 minutes)

#### 4.1 Test ESP32 Local Endpoints

```bash
# 1. Health Check
curl http://192.168.1.100/health
# Should return: status, IP, signal, voltage, current, relayState

# 2. Get Sensors
curl http://192.168.1.100/sensors
# Should return: voltage, current, power, pf, frequency, temperature

# 3. Set User
curl http://192.168.1.100/set-user/123
# Should return: success: true, userId: 123

# 4. Relay Control
curl http://192.168.1.100/relay/on
curl http://192.168.1.100/relay/off
curl http://192.168.1.100/relay/status
# Should return: success: true, relayState: true/false
```

#### 4.2 Test Sensor Accuracy

**Current Sensor Test:**
```
Without load: 0A (or <0.1A)
With 1000W load @ 230V: ~4.3A
With 2000W load @ 230V: ~8.7A
```

**Voltage Sensor Test:**
```
Multimeter reading: 220V
ESP32 reading: ~220V
Tolerance: ±2V
```

#### 4.3 Test Relay Operation

```
Before testing:
1. Disconnect actual load
2. Use a test LED or bulb instead
3. Verify relay clicks when activated

Test Procedure:
curl http://192.168.1.100/relay/on
→ Relay should click, LED turns on

curl http://192.168.1.100/relay/off
→ Relay should click, LED turns off
```

#### 4.4 Test Anomaly Detection

```cpp
// In ESP32 loop, temporarily lower threshold:
float POWER_THRESHOLD = 100.0;  // Temporary low threshold

// Activate load >100W
→ Should see anomaly alert
→ Relay should auto-cut off
→ Notification should appear
```

#### 4.5 Test Flutter App

**Test Relay Control Screen:**
1. Open app → Relay Control
2. Wait for sensor data to load
3. Tap "Turn ON" button
4. Verify relay activates and shows in ESP32 logs
5. Check sensor values update in real-time
6. Tap "Turn OFF" button
7. Verify relay deactivates

**Test Prediction Screen:**
1. Open app → Electricity Prediction
2. Wait for data to load
3. Check next hour prediction loads
4. Check tomorrow's prediction loads
5. If anomalies exist, dialog should appear
6. Tap "See Recommendations"
7. Verify tips appear

#### 4.6 Test Notifications

**Anomaly Alert:**
1. Manually trigger anomaly (low threshold)
2. Phone should vibrate
3. Notification should appear with:
   - Title: "Anomaly Alert" or anomaly type
   - Body: Voltage/Current/Power values
4. Swipe notification to dismiss

**Prediction Alert:**
1. Next-day prediction shows anomaly
2. Notification sent with warning
3. Can tap to view prediction screen

---

## Backend Server Integration

### Required Endpoints:

Create these on your backend (Node.js/Express):

```javascript
// POST /api/esp32/data
router.post('/api/esp32/data', async (req, res) => {
  const { userId, voltage, current, power, energy, timestamp } = req.body;
  // Store in database
  // Trigger ML prediction
  // Check for anomalies
  res.json({ success: true, message: 'Data stored' });
});

// POST /api/anomaly/detect
router.post('/api/anomaly/detect', async (req, res) => {
  const { userId, voltage, current, power, anomalyType } = req.body;
  // Log anomaly
  // Send push notification
  // Alert user
  res.json({ success: true, notified: true });
});

// GET /api/ml-predict/next-hour/:userId
router.get('/api/ml-predict/next-hour/:userId', async (req, res) => {
  // Get historical data
  // Run ML prediction
  res.json({
    success: true,
    prediction: {
      predictedPower: 1250.5,
      confidence: 0.92,
      trend: 'stable',
      recommendation: 'Power usage is normal'
    }
  });
});

// GET /api/ml-predict/next-day/:userId
router.get('/api/ml-predict/next-day/:userId', async (req, res) => {
  res.json({
    success: true,
    prediction: {
      predictedDailyEnergy: 24.5,
      predictedPeakPower: 5200,
      confidence: 0.88,
      anomalyDetected: false,
      adviceIfAnomalous: ''
    }
  });
});

// GET /api/ml-predict/anomalies/:userId
router.get('/api/ml-predict/anomalies/:userId', async (req, res) => {
  res.json({
    success: true,
    anomalies: [
      {
        type: 'Overvoltage',
        description: 'Voltage exceeded 250V',
        timestamp: '2024-01-19T10:30:00Z'
      }
    ]
  });
});

// GET /api/ml-predict/recommendations/:userId
router.get('/api/ml-predict/recommendations/:userId', async (req, res) => {
  res.json({
    success: true,
    recommendations: [
      'Turn off AC during peak hours',
      'Use LED lights instead of incandescent',
      'Schedule heavy loads during night hours'
    ]
  });
});
```

---

## Troubleshooting Checklist

- [ ] ESP32 connects to WiFi
- [ ] ESP32 can reach backend server
- [ ] Sensor readings are within expected range
- [ ] Relay responds to on/off commands
- [ ] App can connect to ESP32
- [ ] App displays sensor values
- [ ] Relay control buttons work
- [ ] Predictions load without error
- [ ] Notifications appear on anomaly
- [ ] ML predictions are reasonable
- [ ] History is being stored

---

## Performance Metrics

After setup, you should see:

**ESP32:**
- WiFi signal: -40 to -60 dBm (good)
- Response time: <100ms
- Memory usage: ~70%
- Data rate: 1 request every 10 seconds

**Flutter App:**
- Screen load time: <2 seconds
- Scroll performance: 60 FPS
- Memory: <150MB
- Battery: ~5% per hour

---

## Security Considerations

1. **WiFi:** Use WPA2 encryption
2. **Server:** Use HTTPS in production
3. **Data:** Encrypt sensitive data
4. **Access:** Implement user authentication
5. **Firmware:** Keep ESP32 firmware updated

---

## Maintenance Schedule

**Daily:**
- Monitor anomaly alerts
- Check sensor readings

**Weekly:**
- Review energy consumption trends
- Check relay operation logs

**Monthly:**
- Calibrate sensors if needed
- Update ML models
- Clean sensor contacts

**Quarterly:**
- Full system audit
- Firmware update
- Relay inspection

---

## Support & Debugging

**Enable verbose logging:**
```cpp
#define DEBUG 1
#if DEBUG
  Serial.println("Debug info");
#endif
```

**Check logs:**
```bash
# ESP32
Open Serial Monitor at 115200 baud

# Flutter
flutter logs

# Backend
tail -f server.log | grep "esp32"
```

---

## Success Indicators ✅

You'll know everything is working when:

1. ✅ ESP32 shows "WiFi Connected" in serial
2. ✅ App displays real-time sensor values
3. ✅ Relay clicks when toggle button pressed
4. ✅ Prediction screen loads data
5. ✅ Anomaly notifications appear
6. ✅ Energy recommendations show
7. ✅ Historical data persists
8. ✅ ML predictions are reasonable

---

## Next Steps

1. **Deploy to production:**
   - Set up backend database
   - Configure production server
   - Set up SSL certificates

2. **Expand features:**
   - Add multi-device support
   - Implement user schedules
   - Add cost estimation

3. **Optimize performance:**
   - Cache predictions
   - Reduce API calls
   - Batch data updates

4. **Enhanced safety:**
   - Add fire detection
   - Email notifications
   - Emergency contacts

---

**Created:** January 19, 2026
**Version:** 1.0
**Status:** Ready for Deployment ✅
