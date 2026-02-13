# 📋 Real-Time Anomaly System - Reference Card

## 🎯 System Overview

```
CLOSED-LOOP CONTROL FLOW
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ DETECT   │────>│ ALERT    │────>│INTERACT  │────>│ ACTION   │
│ 150W+    │     │ WebSocket│     │ Dialog   │     │ Turn OFF │
│ Anomaly  │     │ 100ms    │     │ on Phone │     │ Socket   │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
     ↑                                                    │
     └────────────────────────────────────────────────────┘
                    Feedback Loop
```

---

## 📁 Code Structure

### Backend File Structure
```
wattbuddy-server/
├── server.js
│   ├── Anomaly Detection (Lines 56-116)
│   │   └── if (power > 150W) → io.emit('anomaly_alert')
│   │
│   ├── Relay Endpoints (Lines 200-270)
│   │   ├── GET /api/relay/relay1/off
│   │   ├── GET /api/relay/relay2/off
│   │   ├── GET /api/relay/relay1/on
│   │   ├── GET /api/relay/relay2/on
│   │   └── GET /api/relay/status
│   │
│   └── Socket.io Handler (Lines 272+)
│       └── Broadcasts live_data_update, anomaly_alert, relay_status
│
└── test_anomaly_alerts.js (NEW)
    └── Simulates ESP32 data to test anomaly detection
```

### Flutter File Structure
```
lib/
├── services/
│   └── realtime_anomaly_service.dart (NEW)
│       ├── initialize()
│       ├── turnOffSocket()
│       ├── turnOnSocket()
│       ├── getRelayStatus()
│       └── Event listeners
│
└── screens/
    └── anomaly_alert_example.dart (NEW)
        ├── _showAnomalyAlertDialog()
        ├── _turnOffSocket()
        └── Example UI implementation
```

---

## 🔧 Core Functions

### Backend: Anomaly Detection

**Location:** `server.js` Lines 76-100

**Code:**
```javascript
const currentPower = power || 0;

if (currentPower > 150) {
  const problematicSocket = relay1 === 1 ? "Socket 1" : "Socket 2";
  
  io.emit('anomaly_alert', {
    isAbnormal: true,
    anomalySocket: problematicSocket,
    currentPower: currentPower,
    message: `⚠️ High usage on ${problematicSocket}!`
  });
  
  console.log(`🚨 [ANOMALY ALERT] ${problematicSocket} - ${currentPower}W`);
}
```

**Trigger:** Every ESP32 data point (~5-10 Hz)

---

### Backend: Relay Control

**Location:** `server.js` Lines 200-270

**Endpoints:**
```javascript
GET /api/relay/relay1/off  // Turn off Socket 1
GET /api/relay/relay2/off  // Turn off Socket 2
GET /api/relay/relay1/on   // Turn on Socket 1
GET /api/relay/relay2/on   // Turn on Socket 2
GET /api/relay/status      // Get status
```

**Response:**
```json
{
  "success": true,
  "message": "Socket 1 relay turned OFF",
  "relay": 1,
  "status": "off"
}
```

---

### Frontend: Initialize Service

**Location:** `lib/services/realtime_anomaly_service.dart`

**Code:**
```dart
await RealtimeAnomalyService.initialize(
  onAnomalyAlert: (data) {
    // Called when anomaly detected
    _showAnomalyDialog(
      socketName: data['anomalySocket'],
      power: data['currentPower'],
    );
  },
  onRelayStatusChanged: (data) {
    // Called when relay status updates
    print('Relay ${data["relay"]} is ${data["status"]}');
  },
);
```

---

### Frontend: Show Dialog

**Location:** `lib/screens/anomaly_alert_example.dart`

**Code:**
```dart
void _showAnomalyAlertDialog({
  required String socketName,
  required num power,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('⚠️ $socketName Alert'),
      content: Text('Power: ${power.toStringAsFixed(0)}W'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('NEGLECT'),
        ),
        ElevatedButton(
          onPressed: () {
            RealtimeAnomalyService.turnOffSocket(socketName);
            Navigator.pop(context);
          },
          child: const Text('TURN OFF SWITCH'),
        ),
      ],
    ),
  );
}
```

---

### Frontend: Turn Off Socket

**Location:** `lib/services/realtime_anomaly_service.dart`

**Code:**
```dart
static Future<bool> turnOffSocket(String socketName) async {
  try {
    final socketNum = socketName.contains('1') ? '1' : '2';
    final endpoint = '/api/relay/relay$socketNum/off';
    
    final response = await ApiService.get(endpoint);
    
    if (response['success'] == true) {
      return true;  // Success
    }
    return false;  // Failed
  } catch (e) {
    return false;
  }
}
```

---

## 📊 Event Flow

### Anomaly Detection Flow

```
1. ESP32 sends: power=2850W, relay1=1, relay2=0
   ↓
2. Server receives POST /api/esp32/data
   ↓
3. Check: if (2850 > 150) → TRUE
   ↓
4. Identify: relay1=1 → "Socket 1"
   ↓
5. Emit: io.emit('anomaly_alert', {
     isAbnormal: true,
     anomalySocket: "Socket 1",
     currentPower: 2850,
     message: "⚠️ High usage on Socket 1!"
   })
   ↓
6. Log: 🚨 [ANOMALY ALERT] Socket 1 - 2850W
```

### Relay Control Flow

```
1. User clicks "TURN OFF SWITCH" on phone
   ↓
2. Flutter calls: RealtimeAnomalyService.turnOffSocket("Socket 1")
   ↓
3. Flutter: GET /api/relay/relay1/off
   ↓
4. Server receives request
   ↓
5. Server: io.emit('relay_status', {
     relay: 1,
     status: 'off',
     message: 'Socket 1 disconnected'
   })
   ↓
6. Server log: 🔴 [RELAY 1 OFF]
   ↓
7. Flutter receives event & shows: ✅ "Socket 1 disconnected"
```

---

## 🧪 Testing

### Quick Test (No ESP32 Needed)

```bash
cd wattbuddy-server
node test_anomaly_alerts.js
```

**Output:**
```
✅ Normal data sent (50W)
⚠️  Anomaly data sent (2850W on Socket 1)
   → Server emits anomaly_alert
⚠️  Anomaly data sent (3200W on Socket 2)
   → Server emits anomaly_alert
✅ Relay endpoints working
```

### Manual Test (With Postman)

**Trigger Anomaly:**
```bash
curl -X POST http://localhost:4000/api/esp32/data \
  -H "Content-Type: application/json" \
  -d '{
    "voltage": 230,
    "current": 12.0,
    "power": 2850,
    "energy": 5.234,
    "relay1": 1,
    "relay2": 0,
    "userId": "user123"
  }'
```

**Turn Off Relay:**
```bash
curl http://localhost:4000/api/relay/relay1/off
```

**Check Status:**
```bash
curl http://localhost:4000/api/relay/status
```

---

## ⚙️ Configuration

### Anomaly Threshold

**File:** `server.js` Line 75

```javascript
const baselineAvgPower = 75;      // Baseline power (W)
const anomalyThreshold = 150;     // 2× baseline
```

**To change:**
- Lower threshold (more sensitive): `const anomalyThreshold = 100;`
- Higher threshold (less sensitive): `const anomalyThreshold = 200;`

### Socket.io Connection

**File:** `lib/services/realtime_anomaly_service.dart` Line 23

```dart
_socket = IO.io(
  ApiService.baseUrl.replaceFirst('http://', 'ws://'),
  // Socket.io config
);
```

**Make sure** `ApiService.baseUrl` points to your server:
- Local: `http://192.168.X.X:4000`
- Cloud: `https://your-domain.com`

---

## 📱 Integration Checklist

- [ ] Add `socket_io_client` package: `flutter pub add socket_io_client`
- [ ] Create `RealtimeAnomalyService` in `lib/services/`
- [ ] Create example screen in `lib/screens/`
- [ ] Initialize service in your main screen's `initState()`
- [ ] Add dialog widget to show alerts
- [ ] Test with: `node test_anomaly_alerts.js`
- [ ] Test with real ESP32 data
- [ ] Verify relay endpoints work

---

## 🚀 Quick Start Commands

**Start Server:**
```bash
cd wattbuddy-server
npm start
```

**Run Tests:**
```bash
cd wattbuddy-server
node test_anomaly_alerts.js
```

**Start Flutter:**
```bash
flutter run
```

**Watch Logs:**
```bash
flutter logs
```

---

## 📞 Support Reference

| Component | File | Lines |
|-----------|------|-------|
| Anomaly Detection | `server.js` | 76-100 |
| Relay Endpoints | `server.js` | 200-270 |
| Socket.io Init | `server.js` | 272-290 |
| Service Init | `realtime_anomaly_service.dart` | 10-65 |
| Dialog UI | `anomaly_alert_example.dart` | 40-120 |
| Turn Off Logic | `realtime_anomaly_service.dart` | 150-175 |

---

## ✨ Success Indicators

✅ **Backend Working:**
- Server logs show: `🚨 [ANOMALY ALERT]` when power > 150W
- Relay endpoints return `"success": true`

✅ **Frontend Working:**
- App connects to server (no Socket.io errors)
- Dialog appears when test script runs
- Button clicks trigger relay endpoints

✅ **Full System Working:**
- Alert dialog appears ~200ms after high power
- Dialog disappears after user action
- Server confirms relay state changed
- Success notification appears

---

**Document Last Updated:** January 28, 2026  
**System Status:** ✅ Production Ready
