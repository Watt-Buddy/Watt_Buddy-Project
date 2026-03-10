import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

import '../services/api_service.dart';
import '../services/realtime_anomaly_service.dart';
import '../utils/responsive_scaffold.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool relay1Status = false;
  bool relay2Status = false;
  bool isLoading = false;
  bool isControlling = false;

  double voltage = 0.0;
  double current = 0.0;
  double power = 0.0;
  bool anomalyDetected = false;
  DateTime lastUpdate = DateTime.now();
  // (removed local alert tracking vars; always alert when over threshold)
  bool _isAlertDialogOpen = false;

  // Per-socket alert muting (5 minutes after dismissal or turn-off)
  Set<String> _mutedSockets = {}; // e.g., {'Socket 1', 'Socket 2'}
  static const Duration _socketMuteDuration = Duration(minutes: 5);
  Map<String, DateTime> _socketMuteTime =
      {}; // Track when each socket was muted

  /// Check if a specific socket is muted
  bool _isSocketMuted(String socketName) {
    if (!_mutedSockets.contains(socketName)) return false;
    final muteTime = _socketMuteTime[socketName];
    if (muteTime == null) return false;
    final timeSinceMute = DateTime.now().difference(muteTime);
    if (timeSinceMute >= _socketMuteDuration) {
      // Mute period expired, unmute the socket
      _mutedSockets.remove(socketName);
      _socketMuteTime.remove(socketName);
      return false;
    }
    return true;
  }

  /// Mute a specific socket for 5 minutes
  void _muteSocket(String socketName) {
    if (mounted) {
      setState(() {
        _mutedSockets.add(socketName);
        _socketMuteTime[socketName] = DateTime.now();
      });
    }
  }

  /// Get remaining mute time for a socket in seconds
  int _getRemainingMuteSeconds(String socketName) {
    final muteTime = _socketMuteTime[socketName];
    if (muteTime == null) return 0;
    final timeSinceMute = DateTime.now().difference(muteTime);
    final remaining = _socketMuteDuration.inSeconds - timeSinceMute.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  // Anomaly detection state
  Map<String, dynamic>? _lastAnomalyData;
  bool _isAnomalyServiceConnected = false;

  String relay1Name = "Device 1";
  String relay2Name = "Device 2";
  List<Map<String, dynamic>> devices = [];

  Timer? _refreshTimer;

  // Goal tracking / carryforward / rewards
  double dailyGoalWh = 0.0; // stored in Wh
  double monthlyGoalWh = 0.0; // stored in Wh
  double carryforwardWh = 0.0; // deficit carried to next day (Wh)
  double dailyConsumptionWh = 0.0; // accumulated for today (Wh)
  int rewardPoints = 0;
  DateTime? _lastConsumptionTimestamp;
  DateTime?
      _lastConsumptionDate; // date of the last stored consumption (yyyy-mm-dd)

  // Chart variables
  List<FlSpot> powerDataPoints = [];
  List<FlSpot> voltageDataPoints = [];
  List<FlSpot> currentDataPoints = [];
  double timerCount = 0;

  // ESP32 Direct IP - Must match your ESP32 IP shown in Serial Monitor
  final String esp32Ip = "192.168.137.226";

  @override
  void initState() {
    super.initState();
    _loadDeviceNames();
    _loadRelayStatus();
    _loadGoalsAndConsumption();
    _provisionEsp32ForLoggedInUser();
    _initializeAnomalyDetection();
    // Refresh every 3 seconds to avoid spamming the ESP32 while it samples AC
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _loadRelayStatus();
      }
    });
  }

  Future<void> _provisionEsp32ForLoggedInUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedUser = prefs.getString('wattBuddyUser');
      if (storedUser == null) return;

      final user = jsonDecode(storedUser);
      final dynamic id = user['id'];
      if (id == null) return;

      final ok = await ApiService.setESP32User(id.toString());
      if (ok) {
        debugPrint('✅ Devices provisioned ESP32 user: $id');
      } else {
        debugPrint('⚠️ Devices could not provision ESP32 user');
      }
    } catch (e) {
      debugPrint('⚠️ ESP32 user provisioning skipped: $e');
    }
  }

  // Initialize real-time anomaly detection
  Future<void> _initializeAnomalyDetection() async {
    await RealtimeAnomalyService.initialize(
      onAnomalyAlert: (data) {
        setState(() {
          _lastAnomalyData = data;
          anomalyDetected = data['isAbnormal'] == true;
          _isAnomalyServiceConnected = RealtimeAnomalyService.isConnected;
        });

        // Show alert dialog
        _showAnomalyAlertDialog(
          socketName: data['anomalySocket'] ?? 'Unknown Socket',
          power: (data['currentPower'] ?? 0).toDouble(),
          threshold: (data['threshold'] ?? 150).toDouble(),
          message: data['message'] ?? 'High power usage detected',
        );
      },
      onRelayStatusChanged: (data) {
        // Update relay status from Socket.io updates
        debugPrint('🔌 Relay status updated via Socket.io: $data');
      },
    );

    setState(() {
      _isAnomalyServiceConnected = RealtimeAnomalyService.isConnected;
    });
  }

  // Show anomaly alert dialog
  void _showAnomalyAlertDialog({
    required String socketName,
    required double power,
    required double threshold,
    required String message,
  }) {
    // Check if this specific socket is muted
    if (_isSocketMuted(socketName)) {
      final remaining = _getRemainingMuteSeconds(socketName);
      debugPrint('🚨 $socketName muted. Alert suppressed for ${remaining}s');
      return; // Suppress alert if socket is muted
    }

    if (_isAlertDialogOpen) return; // avoid stacking
    setState(() {
      _isAlertDialogOpen = true;
    });
    final dialogFuture = showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A3A),
        title: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠️ Power Spike Alert',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Power: ${power.toStringAsFixed(0)} W',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Threshold: ${threshold.toStringAsFixed(0)} W',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Source: $socketName',
                    style:
                        const TextStyle(color: Colors.cyanAccent, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                anomalyDetected = false;
                _lastAnomalyData = null;
                _isAlertDialogOpen = false;
              });
              // Mute this socket for 5 minutes
              _muteSocket(socketName);
              Navigator.pop(context);
              // Show mute message
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$socketName alerts muted for 5 minutes.'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: const Text(
              'Dismiss',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.pop(context);
              // Mute this socket before turning it off
              _muteSocket(socketName);
              await _turnOffAnomalySocket(socketName);
              if (mounted) {
                setState(() {
                  anomalyDetected = false;
                  _lastAnomalyData = null;
                });
              }
            },
            child: const Text(
              'Turn Off Socket',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    dialogFuture.then((_) {
      if (mounted) {
        setState(() {
          _isAlertDialogOpen = false;
        });
      }
    });
  }

  // Turn off socket causing anomaly
  Future<void> _turnOffAnomalySocket(String socketName) async {
    final success = await RealtimeAnomalyService.turnOffSocket(socketName);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $socketName turned OFF due to high power usage'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      // Refresh relay status
      _loadRelayStatus();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    RealtimeAnomalyService.disconnect();
    super.dispose();
  }

  Future<void> _loadDeviceNames() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      relay1Name = prefs.getString('relay1_name') ?? "Device 1";
      relay2Name = prefs.getString('relay2_name') ?? "Device 2";
    });
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceList = prefs.getStringList('device_list') ?? [];
    setState(() {
      devices = deviceList.map((d) {
        final parts = d.split('|');
        return {
          'id': parts[0],
          'name': parts[1],
          'relay': int.parse(parts[2]),
        };
      }).toList();
    });
  }

  Future<void> _saveDeviceNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('relay1_name', relay1Name);
    await prefs.setString('relay2_name', relay2Name);
  }

  Future<void> _addDevice(String name, int relay) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = prefs.getStringList('device_list') ?? [];
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    devices.add('$id|$name|$relay');
    await prefs.setStringList('device_list', devices);
    _loadDevices();
    _showSuccessSnackBar("Device '$name' added successfully!");
  }

  Future<void> _removeDevice(String id) async {
    final prefs = await SharedPreferences.getInstance();
    var devices = prefs.getStringList('device_list') ?? [];
    devices.removeWhere((d) => d.startsWith('$id|'));
    await prefs.setStringList('device_list', devices);
    _loadDevices();
    _showSuccessSnackBar("Device removed!");
  }

  Future<void> _loadRelayStatus() async {
    if (!mounted) return;

    try {
      // 1. Fetch from your Node.js Backend (:4000/esp32/latest)
      final response = await ApiService.getRelayStatus();

      // Debug print to see exactly what arrives in the app
      debugPrint('📡 RAW BACKEND RESPONSE: $response');

      // Check if response is valid and not empty
      if (response.isNotEmpty) {
        // Handle both direct data and nested data structure
        final liveData = response['data'] ?? response;

        if (liveData.isEmpty) {
          debugPrint('⚠️ No data in response');
          return;
        }

        if (!mounted) return;
        setState(() {
          // Use liveData instead of response to avoid the 0.0 values
          voltage = ((liveData['voltage'] ?? 0.0) as num).toDouble();
          current = ((liveData['current'] ?? 0.0) as num).toDouble();
          power = ((liveData['power'] ?? 0.0) as num).toDouble();

          debugPrint(
              '✅ Raw Values from backend: V=$voltage, I=$current, P=$power');

          // --- ADD TO CHART LOGIC (only add if power is non-zero) ---
          timerCount += 3; // Matching your 3-second timer interval
          powerDataPoints.add(FlSpot(timerCount, power));
          voltageDataPoints.add(FlSpot(timerCount, voltage));
          currentDataPoints.add(FlSpot(timerCount, current));

          // Keep only the last 20 points (last 1 minute of data)
          if (powerDataPoints.length > 20) powerDataPoints.removeAt(0);
          if (voltageDataPoints.length > 20) voltageDataPoints.removeAt(0);
          if (currentDataPoints.length > 20) currentDataPoints.removeAt(0);

          debugPrint(
              '📊 Chart Points: ${powerDataPoints.length}, Latest: ${power.toStringAsFixed(2)}W');

          // Correctly sync relay status (1 = true/ON, 0 = false/OFF)
          if (!isControlling) {
            relay1Status = ((liveData['relay1'] ?? 0) as num).toInt() == 1;
            relay2Status = ((liveData['relay2'] ?? 0) as num).toInt() == 1;
          }

          lastUpdate = DateTime.now();
        });

        // Accumulate energy consumption based on received instantaneous power
        try {
          await _updateConsumption(power);
        } catch (e) {
          debugPrint('⚠️ Consumption update error: $e');
        }

        debugPrint(
            '✅ Values Decoded: V=$voltage, I=$current, P=$power, R1=$relay1Status, R2=$relay2Status');
      } else {
        debugPrint('⚠️ Empty response from backend');
      }
    } catch (e) {
      debugPrint('⚠️ Fetch error: $e');
      // No fallback - use backend bridge exclusively
    }
  }

  // --- Goal & Consumption Persistence and Logic ---
  Future<void> _loadGoalsAndConsumption() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      dailyGoalWh = (prefs.getDouble('daily_goal_wh') ?? 0.0);
      monthlyGoalWh = (prefs.getDouble('monthly_goal_wh') ?? 0.0);
      carryforwardWh = (prefs.getDouble('carryforward_wh') ?? 0.0);
      dailyConsumptionWh = (prefs.getDouble('daily_consumption_wh') ?? 0.0);
      rewardPoints = (prefs.getInt('reward_points') ?? 0);
      final lastDateStr = prefs.getString('last_consumption_date');
      _lastConsumptionDate =
          lastDateStr != null ? DateTime.tryParse(lastDateStr) : null;
      _lastConsumptionTimestamp = DateTime.now();
    });
  }

  Future<void> _saveGoals() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('daily_goal_wh', dailyGoalWh);
    await prefs.setDouble('monthly_goal_wh', monthlyGoalWh);
    await prefs.setDouble('carryforward_wh', carryforwardWh);
    await prefs.setDouble('daily_consumption_wh', dailyConsumptionWh);
    await prefs.setInt('reward_points', rewardPoints);
    if (_lastConsumptionDate != null) {
      await prefs.setString(
          'last_consumption_date', _lastConsumptionDate!.toIso8601String());
    }
  }

  // Call this whenever new instantaneous power (W) is received to accumulate energy (Wh)
  Future<void> _updateConsumption(double powerW) async {
    final now = DateTime.now();
    // compute delta seconds since last sample
    final last = _lastConsumptionTimestamp ?? now;
    final deltaSec = now.difference(last).inSeconds;
    final seconds = (deltaSec > 0) ? deltaSec : 3; // fallback to 3s

    // Wh += W * (s / 3600)
    final addedWh = powerW * (seconds / 3600.0);

    // Check for day rollover (if stored last date is not today)
    await _checkEndOfDayRollover(now);

    setState(() {
      dailyConsumptionWh += addedWh;
      _lastConsumptionTimestamp = now;
      _lastConsumptionDate = DateTime(now.year, now.month, now.day);
    });

    await _saveGoals();

    // If effective goal exists and usage is below, optionally assign immediate rewards
    final effectiveGoalWh = dailyGoalWh + carryforwardWh;
    if (effectiveGoalWh > 0 && dailyConsumptionWh < effectiveGoalWh) {
      // not assigning here automatically so user doesn't get repeated points; reward on rollover
    }
  }

  // At load/update, check if we've moved to a new day and perform rollover
  Future<void> _checkEndOfDayRollover(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final storedDate = _lastConsumptionDate ??
        (prefs.getString('last_consumption_date') != null
            ? DateTime.tryParse(prefs.getString('last_consumption_date')!)
            : null);

    final today = DateTime(now.year, now.month, now.day);
    if (storedDate == null) {
      // initialize stored date to today
      _lastConsumptionDate = today;
      await prefs.setString('last_consumption_date', today.toIso8601String());
      return;
    }

    final storedDay =
        DateTime(storedDate.year, storedDate.month, storedDate.day);
    if (storedDay.isBefore(today)) {
      // Rollover: evaluate previous day's consumption against that day's effective goal
      final prevEffectiveGoal = dailyGoalWh + carryforwardWh;
      final prevConsumption =
          prefs.getDouble('daily_consumption_wh') ?? dailyConsumptionWh;

      if (prevConsumption < prevEffectiveGoal) {
        // assign reward for previous day
        _assignReward(prevEffectiveGoal, prevConsumption);
        // reset carryforward
        carryforwardWh = 0.0;
      } else {
        // deficit -> carryforward to next day
        final deficit = prevConsumption - prevEffectiveGoal;
        carryforwardWh = deficit;
      }

      // reset daily consumption for new day
      dailyConsumptionWh = 0.0;
      _lastConsumptionDate = today;
      await _saveGoals();
    }
  }

  void _assignReward(double goalWh, double consumptionWh) async {
    if (goalWh <= consumptionWh) return; // no reward
    final savedWh = goalWh - consumptionWh;
    // Reward points: 1 point per full kWh saved
    final savedKwh = savedWh / 1000.0;
    final points = savedKwh.floor();
    if (points <= 0) return;

    setState(() {
      rewardPoints += points;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reward_points', rewardPoints);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '🎉 You earned $points reward point(s) for saving ${savedKwh.toStringAsFixed(2)} kWh!'),
        backgroundColor: Colors.green,
      ));
    }
  }

  void _showGoalsDialog() {
    final dailyController =
        TextEditingController(text: (dailyGoalWh / 1000.0).toStringAsFixed(2));
    final monthlyController = TextEditingController(
        text: (monthlyGoalWh / 1000.0).toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A3A),
        title: const Text('Goals & Rewards',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dailyController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Daily goal (kWh)',
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: monthlyController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Monthly goal (kWh)',
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Carryforward',
                    style: TextStyle(color: Colors.white70)),
                Text('${(carryforwardWh / 1000.0).toStringAsFixed(3)} kWh',
                    style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Reward Points',
                    style: TextStyle(color: Colors.white70)),
                Text('$rewardPoints',
                    style: const TextStyle(color: Colors.greenAccent)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF00D4FF))),
          ),
          TextButton(
            onPressed: () async {
              // Save goals (kWh -> Wh)
              final d = double.tryParse(dailyController.text) ?? 0.0;
              final m = double.tryParse(monthlyController.text) ?? 0.0;
              setState(() {
                dailyGoalWh = d * 1000.0;
                monthlyGoalWh = m * 1000.0;
              });
              await _saveGoals();
              Navigator.pop(context);
              _showSuccessSnackBar('Goals updated');
            },
            child:
                const Text('Save', style: TextStyle(color: Color(0xFF00D4FF))),
          ),
        ],
      ),
    );
  }

  // FIXED: Use Backend Bridge API for relay control
  Future<void> _toggleRelay(int relayNumber) async {
    if (isControlling) return;

    bool currentState = (relayNumber == 1) ? relay1Status : relay2Status;
    bool newState = !currentState;

    try {
      debugPrint(
          "🚀 Sending relay $relayNumber command: ${newState ? 'ON' : 'OFF'}");

      // Optimistic UI update: flip the switch immediately
      setState(() {
        isControlling = true;
        if (relayNumber == 1) {
          relay1Status = newState;
        } else {
          relay2Status = newState;
        }
      });

      bool success;
      // Directly control ESP32 relays so the physical device toggles ON/OFF
      if (relayNumber == 1) {
        success = newState
            ? await ApiService.controlESP32Relay1On()
            : await ApiService.controlESP32Relay1Off();
      } else {
        success = newState
            ? await ApiService.controlESP32Relay2On()
            : await ApiService.controlESP32Relay2Off();
      }

      if (success) {
        _showSuccessSnackBar(
            "Device $relayNumber turned ${newState ? 'ON' : 'OFF'}");
      } else {
        // Revert UI if backend/ESP32 reported failure
        setState(() {
          if (relayNumber == 1) {
            relay1Status = currentState;
          } else {
            relay2Status = currentState;
          }
        });
        throw Exception("ESP32 relay command failed");
      }
    } catch (e) {
      debugPrint("❌ Control Error: $e");
      _showErrorSnackBar("Failed to control device. Ensure server is running.");
    } finally {
      if (mounted) {
        setState(() => isControlling = false);
      }
    }
  }

  Future<void> _editDeviceName(int relayNumber) async {
    TextEditingController nameController = TextEditingController(
      text: relayNumber == 1 ? relay1Name : relay2Name,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1A1A3A),
        title: Text(
          "Edit Device Name",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Enter device name",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00D4FF)),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF00D4FF), width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Color(0xFF00D4FF))),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                if (relayNumber == 1) {
                  relay1Name = nameController.text;
                } else {
                  relay2Name = nameController.text;
                }
              });
              _saveDeviceNames();
              Navigator.pop(context);
              _showSuccessSnackBar("Device name updated");
            },
            child: Text("Save", style: TextStyle(color: Color(0xFF00D4FF))),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Build the live chart widget (single graph with Power, Voltage, Current)
  Widget _buildLiveChart() {
    final latestPower =
        powerDataPoints.isNotEmpty ? powerDataPoints.last.y : 0.0;
    final latestVoltage =
        voltageDataPoints.isNotEmpty ? voltageDataPoints.last.y : 0.0;
    final latestCurrent =
        currentDataPoints.isNotEmpty ? currentDataPoints.last.y : 0.0;

    // Calculate dynamic maxY based on actual data with 20% headroom
    double dynamicMaxY = 300.0; // Default minimum
    if (powerDataPoints.isNotEmpty) {
      final maxPower =
          powerDataPoints.map((p) => p.y).fold(0.0, (a, b) => a > b ? a : b);
      final maxVoltage = voltageDataPoints.isNotEmpty
          ? voltageDataPoints.map((p) => p.y).fold(0.0, (a, b) => a > b ? a : b)
          : 0.0;
      final maxCurrent = currentDataPoints.isNotEmpty
          ? currentDataPoints.map((p) => p.y).fold(0.0, (a, b) => a > b ? a : b)
          : 0.0;

      final maxValue =
          [maxPower, maxVoltage, maxCurrent].reduce((a, b) => a > b ? a : b);
      dynamicMaxY = (maxValue * 1.2); // Add 20% headroom

      // Round to nearest 50 for clean Y-axis labels
      dynamicMaxY = ((dynamicMaxY / 50).ceil() * 50).toDouble();
      dynamicMaxY =
          dynamicMaxY < 300 ? 300 : dynamicMaxY; // Minimum 300 for readability
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00D4FF), width: 1),
      ),
      child: Stack(
        children: [
          LineChart(
            LineChartData(
              minY: 0,
              maxY: dynamicMaxY, // Auto-adjusted based on actual consumption
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 50,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.white.withOpacity(0.04),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: 50,
                    getTitlesWidget: (value, meta) {
                      // show tidy Y axis labels at 0,50,100...
                      if (value % 50 != 0) return const SizedBox.shrink();
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: Colors.black87,
                  getTooltipItems: (spots) {
                    return spots.map((s) {
                      return LineTooltipItem(
                        '${s.y.toStringAsFixed(1)} W',
                        const TextStyle(color: Colors.white),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                // Power line (Watts)
                LineChartBarData(
                  spots: powerDataPoints,
                  isCurved: true,
                  color: const Color(0xFF4ECDC4),
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF4ECDC4).withOpacity(0.18),
                        const Color(0xFF4ECDC4).withOpacity(0.02),
                      ],
                    ),
                  ),
                ),
                // Voltage line (Volts)
                LineChartBarData(
                  spots: voltageDataPoints,
                  isCurved: true,
                  // color: const Color(0xFF4ECDC4),
                  color: const Color(0xFF00D4FF),
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                // Current line (Amps) – same axis for simplicity
                LineChartBarData(
                  spots: currentDataPoints,
                  isCurved: true,
                  color: const Color(0xFFFF6B6B),
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),

          // Latest value badge (shows all three)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFF00D4FF).withOpacity(0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${latestPower.toStringAsFixed(1)} W',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                  Text(
                    '${latestVoltage.toStringAsFixed(1)} V',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9), fontSize: 11),
                  ),
                  Text(
                    '${latestCurrent.toStringAsFixed(3)} A',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddDeviceDialog() {
    final TextEditingController nameController = TextEditingController();
    int selectedRelay = 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Color(0xFF1A1A3A),
          title: Text(
            "Add New Device",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Device name (e.g., AC, Fan)",
                  hintStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00D4FF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF00D4FF), width: 2),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(
                "Select Relay Channel",
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => selectedRelay = 1),
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedRelay == 1
                              ? Color(0xFF00D4FF).withOpacity(0.2)
                              : Colors.transparent,
                          border: Border.all(
                            color: selectedRelay == 1
                                ? Color(0xFF00D4FF)
                                : Colors.grey,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            "Relay 1",
                            style: TextStyle(
                              color: selectedRelay == 1
                                  ? Color(0xFF00D4FF)
                                  : Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => selectedRelay = 2),
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selectedRelay == 2
                              ? Color(0xFFFF6B6B).withOpacity(0.2)
                              : Colors.transparent,
                          border: Border.all(
                            color: selectedRelay == 2
                                ? Color(0xFFFF6B6B)
                                : Colors.grey,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            "Relay 2",
                            style: TextStyle(
                              color: selectedRelay == 2
                                  ? Color(0xFFFF6B6B)
                                  : Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Color(0xFF00D4FF))),
            ),
            TextButton(
              onPressed: () {
                if (nameController.text.isEmpty) {
                  _showErrorSnackBar("Please enter a device name");
                  return;
                }
                _addDevice(nameController.text, selectedRelay);
                Navigator.pop(context);
              },
              child: Text("Add", style: TextStyle(color: Color(0xFF00D4FF))),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: 'Devices',
      body: Container(
        color: Color(0xFF0A0A2A),
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadRelayStatus();
          },
          color: Color(0xFF00D4FF),
          backgroundColor: Color(0xFF1A1A3A),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Refresh Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Manage Devices",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Control your 2-channel relay devices",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Color(0xFF00D4FF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: Color(0xFF00D4FF), width: 1),
                          ),
                          child: IconButton(
                            icon: Icon(Icons.refresh,
                                color: Color(0xFF00D4FF), size: 28),
                            onPressed: _loadRelayStatus,
                            tooltip: 'Pull down to refresh or tap here',
                            iconSize: 28,
                          ),
                        ),
                        SizedBox(width: 8),
                        // Goals settings
                        Container(
                          decoration: BoxDecoration(
                            color: Color(0xFF1A1A3A),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: Color(0xFF00D4FF), width: 1),
                          ),
                          child: IconButton(
                            icon: Icon(Icons.tune,
                                color: Color(0xFF00D4FF), size: 24),
                            onPressed: _showGoalsDialog,
                            tooltip: 'Set daily/monthly goals',
                          ),
                        ),
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: _showAddDeviceDialog,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Color(0xFF00D4FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.add, color: Colors.black, size: 20),
                                SizedBox(width: 6),
                                Text(
                                  "Add Device",
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 30),

                // Custom Devices List
                if (devices.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Your Devices",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      ...devices.map((device) {
                        final color = device['relay'] == 1
                            ? Color(0xFF00D4FF)
                            : Color(0xFFFF6B6B);
                        return Container(
                          margin: EdgeInsets.only(bottom: 10),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Color(0xFF1A1A3A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: color.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device['name'],
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "Relay ${device['relay']}",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(Icons.delete,
                                    color: Colors.red, size: 18),
                                onPressed: () => _removeDevice(device['id']),
                              ),
                            ],
                          ),
                        );
                      }),
                      SizedBox(height: 20),
                    ],
                  ),

                // Power Consumption History Chart
                Text(
                  "Live Consumption (Power / V / A)",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildLiveChart(),
                const SizedBox(height: 24),

                // Sensor Data Panel
                Text(
                  "Relay 1 & 2 Control",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),

                // Live Sensor Data Section
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFF1A1A3A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Color(0xFF00D4FF), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Live Sensor Data",
                            style: TextStyle(
                              color: Color(0xFF00D4FF),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          GestureDetector(
                            onTap: _loadRelayStatus,
                            child: Icon(Icons.refresh,
                                color: Color(0xFF00D4FF), size: 20),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSensorMetric(
                              "Voltage",
                              "${voltage.toStringAsFixed(1)} V",
                              Icons.electric_bolt,
                              Color(0xFF00D4FF)),
                          _buildSensorMetric(
                              "Current",
                              "${current.toStringAsFixed(2)} A",
                              Icons.flash_on,
                              Color(0xFFFF6B6B)),
                          _buildSensorMetric(
                              "Power",
                              "${power.toStringAsFixed(1)} W",
                              Icons.power_settings_new,
                              Color(0xFF4ECDC4)),
                        ],
                      ),
                      SizedBox(height: 12),
                      // Anomaly Status Indicator
                      if (anomalyDetected || _lastAnomalyData != null)
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red, width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_rounded,
                                      color: Colors.red, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    "⚠️ Anomaly Detected!",
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                              if (_lastAnomalyData != null) ...[
                                SizedBox(height: 8),
                                Text(
                                  _lastAnomalyData!['message'] ??
                                      'High power usage detected',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Power: ${(_lastAnomalyData!['currentPower'] ?? 0).toStringAsFixed(0)}W | Source: ${_lastAnomalyData!['anomalySocket'] ?? 'Unknown'}',
                                  style: TextStyle(
                                      color: Colors.redAccent, fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                      // Socket.io Connection Status
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isAnomalyServiceConnected
                                  ? Colors.green
                                  : Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 6),
                          Text(
                            _isAnomalyServiceConnected
                                ? 'Real-time monitoring active'
                                : 'Real-time monitoring offline',
                            style: TextStyle(
                              color: _isAnomalyServiceConnected
                                  ? Colors.green
                                  : Colors.red,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Last updated: ${lastUpdate.hour}:${lastUpdate.minute.toString().padLeft(2, '0')}:${lastUpdate.second.toString().padLeft(2, '0')}",
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                          if (isLoading)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF00D4FF)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 30),

                // Relay 1 Control Card
                _buildRelayCard(
                  1,
                  relay1Name,
                  relay1Status,
                  Icons.outlet,
                  Color(0xFF00D4FF),
                ),

                SizedBox(height: 16),

                // Relay 2 Control Card
                _buildRelayCard(
                  2,
                  relay2Name,
                  relay2Status,
                  Icons.outlet,
                  Color(0xFFFF6B6B),
                ),

                SizedBox(height: 30),

                // Emergency Stop Button
                GestureDetector(
                  onTap: isControlling ? null : _showEmergencyStopDialog,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.emergency_share,
                            color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Emergency Stop All Devices",
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 12),

                // Turn On All Button
                GestureDetector(
                  onTap: isControlling ? null : _showTurnOnAllDialog,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.power, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Turn On All Devices",
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSensorMetric(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelayCard(
      int relayNumber, String name, bool status, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF1A1A3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: status ? color : Colors.grey.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: status
            ? [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with name and edit button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Relay Channel $relayNumber",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.edit, color: Colors.grey, size: 18),
                onPressed: () => _editDeviceName(relayNumber),
              ),
            ],
          ),

          SizedBox(height: 16),

          // Status and Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Status",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: status
                          ? color.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: status ? color : Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: status ? color : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          status ? "ON" : "OFF",
                          style: TextStyle(
                            color: status ? color : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: isControlling ? null : () => _toggleRelay(relayNumber),
                child: Opacity(
                  opacity: isControlling ? 0.5 : 1.0,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: status ? color : Colors.grey, width: 2),
                    ),
                    child: isControlling
                        ? CircularProgressIndicator(
                            color: color, strokeWidth: 2)
                        : Icon(Icons.power_settings_new,
                            color: status ? color : Colors.grey, size: 32),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEmergencyStopDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1A1A3A),
        title: Text(
          "Emergency Stop",
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to immediately shut down all devices?\nThis cannot be undone instantly.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Color(0xFF00D4FF))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performEmergencyStop();
            },
            child: Text("Yes, Stop All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showTurnOnAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1A1A3A),
        title: Text(
          "Turn On All Devices",
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to turn ON all devices?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: Color(0xFF00D4FF))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performTurnOnAll();
            },
            child: Text("Yes, Turn On", style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  Future<void> _performEmergencyStop() async {
    await _setAllRelays(false);
  }

  Future<void> _performTurnOnAll() async {
    await _setAllRelays(true);
  }

  Future<void> _setAllRelays(bool turnOn) async {
    final actionText = turnOn ? 'TURN ON ALL' : 'EMERGENCY STOP';
    final targetStateText = turnOn ? 'ON' : 'OFF';
    setState(() => isControlling = true);

    try {
      debugPrint('🚨 $actionText: Turning $targetStateText all relays...');

      // Send both relay commands directly to ESP32 in parallel.
      // Backend relay endpoints may fail even when direct ESP32 path is healthy.
      final future1 = turnOn
          ? ApiService.controlESP32Relay1On()
          : ApiService.controlESP32Relay1Off();
      final future2 = turnOn
          ? ApiService.controlESP32Relay2On()
          : ApiService.controlESP32Relay2Off();

      final results = await Future.wait([future1, future2]);
      final relay1Success = results[0];
      final relay2Success = results[1];

      setState(() {
        if (relay1Success) relay1Status = turnOn;
        if (relay2Success) relay2Status = turnOn;
        isControlling = false;
      });

      if (relay1Success && relay2Success) {
        _showSuccessSnackBar(
          turnOn
              ? "🟢 All devices turned ON successfully!"
              : "🚨 All devices shut down successfully!",
        );
        debugPrint('✅ $actionText completed: Both relays $targetStateText');
      } else if (relay1Success || relay2Success) {
        _showErrorSnackBar(
          "⚠️ Partial ${turnOn ? 'turn on' : 'shutdown'}:\n" +
              "${relay1Success ? '✅ Device 1 $targetStateText' : '❌ Device 1 failed'}\n" +
              "${relay2Success ? '✅ Device 2 $targetStateText' : '❌ Device 2 failed'}",
        );
        debugPrint(
            '⚠️ $actionText partial: R1=$relay1Success, R2=$relay2Success');
      } else {
        _showErrorSnackBar(
          "❌ ${turnOn ? 'Turn on all' : 'Emergency stop'} failed!\nCould not reach ESP32 device.\nCheck network connection.",
        );
        debugPrint('❌ $actionText failed: Both relays failed');
      }
    } catch (e) {
      setState(() => isControlling = false);
      _showErrorSnackBar(
          "❌ ${turnOn ? 'Turn on all' : 'Emergency stop'} error: $e");
      debugPrint('❌ $actionText exception: $e');
    }
  }
}
