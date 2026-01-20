# ESP32 Energy Monitor with Sensors - Complete Setup Guide

## Overview
This guide covers the complete integration of:
- ACS712 Current Sensor
- ZMPT101B Voltage Sensor  
- Relay Module for power control
- Flutter UI for control and predictions
- Anomaly detection and notifications

---

## ESP32 Hardware Setup

### Components Needed:
1. **ESP32 Development Board**
2. **ACS712-5A Current Sensor** (or 20A/30A variant)
3. **ZMPT101B Voltage Sensor**
4. **Relay Module** (5V single-channel)
5. **Power Supply** (3.3V for ESP32, 5V for relay)
6. **Jumper wires and breadboard**

### Pin Configuration:
```
ESP32 Pin 35 (GPIO35) → ACS712 OUT (Analog Input)
ESP32 Pin 34 (GPIO34) → ZMPT101B OUT (Analog Input)
ESP32 Pin 23 (GPIO23) → Relay Module IN (Digital Output)
ESP32 GND → Common Ground
```

### Wiring Diagram:

#### ACS712 Current Sensor:
```
5V → Power (VCC)
GND → Ground (GND)
OUT → ESP32 GPIO 35 (ADC1_CHANNEL_7)
```

#### ZMPT101B Voltage Sensor:
```
5V → Power (VCC)
GND → Ground (GND)
OUT → ESP32 GPIO 34 (ADC1_CHANNEL_6)
```

#### Relay Module:
```
5V → Power (VCC)
GND → Ground (GND)
IN → ESP32 GPIO 23 (Digital Output)
```

---

## ESP32 Code Configuration

### 1. Adjust ACS712 Sensitivity
If using different ACS712 variant:
```cpp
// For ACS712-5A (185 mV/A)
const float ACS712_SENSITIVITY = 0.185;

// For ACS712-20A (100 mV/A)
const float ACS712_SENSITIVITY = 0.100;

// For ACS712-30A (66 mV/A)
const float ACS712_SENSITIVITY = 0.066;
```

### 2. Adjust ZMPT101B Sensitivity
Calibrate based on your region:
```cpp
// For 220V regions
const float VOLTAGE_MULTIPLIER = 220.0;

// For 110V regions
const float VOLTAGE_MULTIPLIER = 110.0;
```

### 3. Set Anomaly Thresholds
Adjust based on your needs:
```cpp
float POWER_THRESHOLD = 5000.0;      // Watts
float VOLTAGE_THRESHOLD = 250.0;     // Volts
float CURRENT_THRESHOLD = 20.0;      // Amps
float TEMP_THRESHOLD = 45.0;         // Celsius
```

### 4. WiFi Configuration
```cpp
const char* ssid = "your_wifi_name";
const char* password = "your_wifi_password";
const char* serverUrl = "http://your_server_ip:4000/api/esp32/data";
```

---

## Flutter App Integration

### 1. Add Screens to Navigation
Update your main navigation file to include:

```dart
// In your main navigation
RelayControlScreen(),        // For switch on/off control
ElectricityPredictionScreen(), // For predictions & anomalies
```

### 2. Initialize Notification Service
In your `main.dart`:

```dart
import 'lib/services/anomaly_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AnomalyNotificationService.initialize();
  runApp(const MyApp());
}
```

### 3. Update pubspec.yaml (if not already there)
```yaml
dependencies:
  flutter_local_notifications: ^14.0.0
  http: ^1.1.0
  shared_preferences: ^2.0.0
```

### 4. Android Manifest Update
Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<application
    android:usesCleartextTraffic="true"
    ...>
</application>
```

---

## API Endpoints Required

### ESP32 Local Endpoints:
```
GET  /set-user/{userId}          - Set current user ID
GET  /health                       - Health check
GET  /relay/toggle                 - Toggle relay
GET  /relay/on                     - Turn relay on
GET  /relay/off                    - Turn relay off
GET  /relay/status                 - Get relay status
GET  /sensors                      - Get current sensor readings
```

### Backend Server Endpoints:
```
POST /api/esp32/data               - Store sensor readings
POST /api/anomaly/detect           - Log anomaly detection
GET  /api/anomaly/detect/{userId}  - Get anomalies
POST /api/relay/on                 - Turn on relay
POST /api/relay/off                - Turn off relay
GET  /api/relay/status/{userId}    - Get relay status
GET  /api/ml-predict/next-hour/{userId}    - Hour prediction
GET  /api/ml-predict/next-day/{userId}     - Day prediction
GET  /api/ml-predict/anomalies/{userId}    - Anomaly list
GET  /api/ml-predict/recommendations/{userId} - Tips
```

---

## Testing the Setup

### 1. Test ESP32 Sensors:
Open Serial Monitor at 115200 baud:
```
🔌 ESP32 Energy Monitor with Sensors Starting...
✅ SPIFFS Mounted
📡 Connecting to WiFi: realme C31
✅ WiFi Connected!
📡 ESP32 IP: 192.168.x.x
✅ WebServer started on port 80
```

### 2. Test Current Sensor:
- Without load: Should read ~0A
- With 1000W load: Should read ~4.35A (at 230V)

### 3. Test Voltage Sensor:
- Should read close to your mains voltage (220V or 110V)

### 4. Test Relay:
- Access: `http://esp32-ip/relay/on` to turn on
- Access: `http://esp32-ip/relay/off` to turn off

### 5. Test from Flutter App:
- Open RelayControlScreen
- Tap "Turn ON" button
- Watch relay activate and sensor values update

---

## Troubleshooting

### Sensor Reading Issues:

**Problem: Current sensor always reads 0**
- Check ADC pin connections
- Verify ACS712_SENSITIVITY is correct for your module
- Check if ACS_ZERO_OFFSET (2.5V) matches your sensor

**Problem: Voltage reading is wrong**
- Verify VOLTAGE_MULTIPLIER matches your region (110V or 220V)
- Check ZMPT101B calibration
- Ensure sensor is getting 5V power

**Problem: Relay not working**
- Check relay module power (needs 5V)
- Verify GPIO 23 connection
- Test with: `http://esp32-ip/relay/on`

### WiFi Issues:

**Problem: Cannot connect to server**
- Check WiFi SSID and password
- Verify server URL is correct
- Ensure both ESP32 and phone are on same network
- Check firewall settings

**Problem: Notifications not appearing**
- Enable notifications in app settings
- Check Android "POST_NOTIFICATIONS" permission
- Verify notification channel is created

---

## Calibration Guide

### Calibrate ACS712:
1. Ensure no current is flowing
2. Read ADC value: Should be ~2048 (for 3.3V reference)
3. Set `ACS_ZERO_OFFSET = (adcValue / 4095) * 3.3`

### Calibrate ZMPT101B:
1. Measure actual voltage with multimeter
2. Note ESP32 ADC reading
3. Adjust VOLTAGE_MULTIPLIER to match

### Formula:
```
Actual Voltage = (ADC Reading / 4095) * 3.3 * VOLTAGE_MULTIPLIER
```

---

## Performance Optimization

### Reduce Network Traffic:
Change data sending interval in loop():
```cpp
delay(30000);  // Send every 30 seconds instead of 10
```

### Improve Accuracy:
Increase ADC samples:
```cpp
analogSetSamples(16);  // From 8 to 16 samples
```

### Reduce Power Consumption:
Enable WiFi sleep when idle:
```cpp
WiFi.setSleep(true);
```

---

## Safety Features Implemented

✅ **Auto-cut relay** on overcurrent/overvoltage
✅ **Real-time anomaly detection** 
✅ **Push notifications** for critical alerts
✅ **Anomaly history** for analysis
✅ **User-controlled relay toggle**
✅ **Sensor health monitoring**
✅ **ML-based predictions**

---

## Next Steps

1. Upload ESP32 code to your board
2. Configure WiFi and server URL
3. Add Flutter screens to your app
4. Test all endpoints
5. Monitor logs in Serial Monitor
6. Set anomaly thresholds based on your system

---

## Support & Debugging

Enable debug mode:
```cpp
#define DEBUG true

#if DEBUG
  Serial.println("Debug message");
#endif
```

Check server logs:
```bash
tail -f server.log | grep "esp32"
```

Monitor Flutter logs:
```bash
flutter logs
```

---

## Hardware Specifications

| Component | Spec | Voltage | Current |
|-----------|------|---------|---------|
| ACS712-5A | Hall Effect | 3.3-5V | Max 5A |
| ZMPT101B | Resistive | 3.3-5V | ~0.1A |
| Relay Module | Electromagnetic | 5V | 10A @ 250VAC |
| ESP32 | Microcontroller | 3.3V | 240mA |

---

**Last Updated:** January 2026
**Version:** 1.0
**Author:** WattBuddy Team
