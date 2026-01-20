# ESP32 Energy Monitor - Flutter Integration Guide

## 🔌 Quick Integration Checklist

### 1️⃣ **When User Logs In** (login_register.dart)
```dart
// After successful login, set the user on ESP32
if (response.statusCode == 200) {
  final userId = jsonDecode(response.body)['userId'];
  
  // Tell ESP32 who is logged in
  await ApiService.setESP32User(userId);
  
  // Navigate to dashboard
  Navigator.pushReplacementNamed(context, '/dashboard');
}
```

### 2️⃣ **Display Sensor Readings** (dashboard_screen.dart)
```dart
// Add to your dashboard to show real-time sensor data
FutureBuilder<Map<String, dynamic>>(
  future: ApiService.getESP32Sensors(),
  builder: (context, snapshot) {
    if (snapshot.hasData && snapshot.data!['success'] == true) {
      final voltage = snapshot.data!['voltage'];
      final current = snapshot.data!['current'];
      final power = snapshot.data!['power'];
      final dailyEnergy = snapshot.data!['dailyEnergy'];
      
      return Column(
        children: [
          _buildSensorCard('Voltage', '$voltage V', '🔌'),
          _buildSensorCard('Current', '$current A', '⚡'),
          _buildSensorCard('Power', '$power W', '🔥'),
          _buildSensorCard('Daily Energy', '$dailyEnergy kWh', '📊'),
        ],
      );
    }
    return CircularProgressIndicator();
  },
)
```

### 3️⃣ **Control Relay** (devices_screen.dart)
```dart
// Turn relay ON
onPressed: () async {
  final success = await ApiService.turnESP32RelayOn();
  if (success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Relay turned ON')),
    );
  }
}

// Turn relay OFF
onPressed: () async {
  final success = await ApiService.turnESP32RelayOff();
  if (success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Relay turned OFF')),
    );
  }
}
```

### 4️⃣ **Display Energy Data** (bill_prediction_screen.dart)
```dart
// Show daily and monthly energy consumption
FutureBuilder<Map<String, dynamic>>(
  future: ApiService.getESP32Energy(),
  builder: (context, snapshot) {
    if (snapshot.hasData && snapshot.data!['success'] == true) {
      final dailyEnergy = snapshot.data!['dailyEnergy'];
      final monthlyEnergy = snapshot.data!['monthlyEnergy'];
      
      // Calculate estimated cost: ₹7.50 per kWh in India
      final dailyCost = dailyEnergy * 7.50;
      final monthlyCost = monthlyEnergy * 7.50;
      
      return Column(
        children: [
          Text('Daily: $dailyEnergy kWh (₹${dailyCost.toStringAsFixed(2)})'),
          Text('Monthly: $monthlyEnergy kWh (₹${monthlyCost.toStringAsFixed(2)})'),
        ],
      );
    }
    return SizedBox();
  },
)
```

---

## 📊 **Available API Methods**

### **Sensor Readings**
```dart
// Get all current sensor readings
Map<String, dynamic> sensors = await ApiService.getESP32Sensors();
// Returns: voltage, current, power, relay, totalEnergy, dailyEnergy, monthlyEnergy

// Get relay status
Map<String, dynamic> status = await ApiService.getESP32RelayStatus();
// Returns: relay, voltage, current, power

// Get energy data
Map<String, dynamic> energy = await ApiService.getESP32Energy();
// Returns: totalEnergy, dailyEnergy, monthlyEnergy
```

### **Relay Control**
```dart
// Turn relay ON
bool success = await ApiService.turnESP32RelayOn();

// Turn relay OFF
bool success = await ApiService.turnESP32RelayOff();
```

### **User Management**
```dart
// Set logged-in user on ESP32
bool success = await ApiService.setESP32User('USER_123');
```

---

## 🔧 **Troubleshooting**

| Issue | Solution |
|-------|----------|
| "ESP32 not responding" | Check ESP32 is powered on and connected to WiFi |
| Sensors return 0 | Ensure ACS712 and ZMPT101B are properly connected to GPIO 35 and 34 |
| User not set | Call `setESP32User()` after successful login |
| Relay not responding | Verify GPIO 18 connection and relay module power supply |
| Connection timeout | Check if ESP32 IP is `10.168.130.214`, adjust if needed |

---

## 💡 **Example: Complete Dashboard Integration**

```dart
class DashboardScreen extends StatefulWidget {
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Timer _sensorTimer;

  @override
  void initState() {
    super.initState();
    
    // Refresh sensor data every 5 seconds
    _sensorTimer = Timer.periodic(Duration(seconds: 5), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _sensorTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
        },
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Current Readings
              FutureBuilder<Map<String, dynamic>>(
                future: ApiService.getESP32Sensors(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return CircularProgressIndicator();
                  }
                  
                  if (!snapshot.hasData || snapshot.data!['success'] != true) {
                    return Text('Unable to fetch sensor data');
                  }

                  final data = snapshot.data!;
                  return GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    children: [
                      _sensorCard('Voltage', '${data['voltage']} V', Colors.blue),
                      _sensorCard('Current', '${data['current']} A', Colors.green),
                      _sensorCard('Power', '${data['power']} W', Colors.orange),
                      _sensorCard('Daily', '${data['dailyEnergy']} kWh', Colors.purple),
                    ],
                  );
                },
              ),

              SizedBox(height: 24),

              // Relay Control
              FutureBuilder<Map<String, dynamic>>(
                future: ApiService.getESP32RelayStatus(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return SizedBox();
                  
                  final isOn = snapshot.data!['relay'] ?? false;
                  
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          await ApiService.turnESP32RelayOn();
                          setState(() {});
                        },
                        icon: Icon(Icons.power),
                        label: Text('Turn ON'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isOn ? Colors.green : Colors.grey,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await ApiService.turnESP32RelayOff();
                          setState(() {});
                        },
                        icon: Icon(Icons.power_off),
                        label: Text('Turn OFF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !isOn ? Colors.red : Colors.grey,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sensorCard(String label, String value, Color color) {
    return Card(
      color: color.withOpacity(0.1),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
```

---

## 🚀 **Next Steps**

1. ✅ **Upload corrected ESP32 code** to your ESP32 board
2. ✅ **Update API Service** in Flutter app (done)
3. ✅ **Implement login integration** to set user on ESP32
4. ✅ **Add sensor widgets** to dashboard
5. ✅ **Test relay control** from app
6. ✅ **Monitor backend logs** to verify data is being saved

---

## 📝 **Notes**

- **ESP32 IP:** `10.168.130.214` (change if on different network)
- **Update Frequency:** Sensor data updated every 5 seconds
- **Power Cost:** ₹7.50 per kWh in India (adjust based on your location)
- **Energy Persistence:** Saved to ESP32 SPIFFS, survives power loss
- **User Tracking:** Essential for identifying which user owns the readings

---

**All files ready! Deploy and test 🎉**
