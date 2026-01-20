import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../services/api_service.dart';
import '../utils/responsive_scaffold.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  // Relay States
  bool relay1Status = false;
  bool relay2Status = false;
  bool isLoading = false;
  bool isControlling = false;

  // Sensor Data
  double voltage = 0.0;
  double current = 0.0;
  double power = 0.0;
  bool anomalyDetected = false;
  DateTime lastUpdate = DateTime.now();

  // Device Names
  String relay1Name = "Device 1";
  String relay2Name = "Device 2";

  // Track which relays are configured
  List<Map<String, dynamic>> devices = [];

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDeviceNames();
    _loadRelayStatus();
    // Auto-refresh every 3 seconds
    _refreshTimer = Timer.periodic(Duration(seconds: 3), (_) {
      _loadRelayStatus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
    setState(() => isLoading = true);

    final status = await ApiService.getRelayStatus();

    if (status.isNotEmpty) {
      setState(() {
        relay1Status = status['relay1'] ?? false;
        relay2Status = status['relay2'] ?? false;
        voltage = (status['voltage'] ?? 0).toDouble();
        current = (status['current'] ?? 0).toDouble();
        power = (status['power'] ?? 0).toDouble();
        anomalyDetected = status['anomaly'] ?? false;
        lastUpdate = DateTime.now();
      });
    }

    setState(() => isLoading = false);
  }

  Future<void> _toggleRelay(int relayNumber) async {
    setState(() => isControlling = true);

    bool success = false;
    bool newState = false;

    if (relayNumber == 1) {
      newState = !relay1Status;
      success = await ApiService.controlRelay1(newState);
    } else {
      newState = !relay2Status;
      success = await ApiService.controlRelay2(newState);
    }

    if (success) {
      setState(() {
        if (relayNumber == 1) {
          relay1Status = newState;
        } else {
          relay2Status = newState;
        }
      });
      _showSuccessSnackBar(
        relayNumber == 1
            ? "Relay 1 ${newState ? 'ON' : 'OFF'}"
            : "Relay 2 ${newState ? 'ON' : 'OFF'}",
      );
    } else {
      _showErrorSnackBar("Failed to control relay $relayNumber");
    }

    setState(() => isControlling = false);
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
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
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
                          color: selectedRelay == 1 ? Color(0xFF00D4FF).withOpacity(0.2) : Colors.transparent,
                          border: Border.all(
                            color: selectedRelay == 1 ? Color(0xFF00D4FF) : Colors.grey,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            "Relay 1",
                            style: TextStyle(
                              color: selectedRelay == 1 ? Color(0xFF00D4FF) : Colors.white70,
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
                          color: selectedRelay == 2 ? Color(0xFFFF6B6B).withOpacity(0.2) : Colors.transparent,
                          border: Border.all(
                            color: selectedRelay == 2 ? Color(0xFFFF6B6B) : Colors.grey,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            "Relay 2",
                            style: TextStyle(
                              color: selectedRelay == 2 ? Color(0xFFFF6B6B) : Colors.white70,
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
                          border: Border.all(color: Color(0xFF00D4FF), width: 1),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.refresh, color: Color(0xFF00D4FF), size: 28),
                          onPressed: _loadRelayStatus,
                          tooltip: 'Pull down to refresh or tap here',
                          iconSize: 28,
                        ),
                      ),
                      SizedBox(width: 8),
                      GestureDetector(
                        onTap: _showAddDeviceDialog,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      final color = device['relay'] == 1 ? Color(0xFF00D4FF) : Color(0xFFFF6B6B);
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
                              icon: Icon(Icons.delete, color: Colors.red, size: 18),
                              onPressed: () => _removeDevice(device['id']),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    SizedBox(height: 20),
                  ],
                ),

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

              if (!isLoading)
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
                          _buildSensorMetric("Voltage", "$voltage V",
                              Icons.electric_bolt, Color(0xFF00D4FF)),
                          _buildSensorMetric(
                              "Current",
                              "$current A",
                              Icons.flash_on,
                              Color(0xFFFF6B6B)),
                          _buildSensorMetric("Power", "$power W",
                              Icons.power_settings_new, Color(0xFF4ECDC4)),
                        ],
                      ),
                      SizedBox(height: 12),
                      if (anomalyDetected)
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red, width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_rounded,
                                  color: Colors.red, size: 16),
                              SizedBox(width: 8),
                              Text(
                                "⚠️ Anomaly Detected!",
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(height: 8),
                      Text(
                        "Last updated: ${lastUpdate.hour}:${lastUpdate.minute.toString().padLeft(2, '0')}",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
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
                      Icon(Icons.emergency_share, color: Colors.red, size: 20),
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

  Widget _buildRelayCard(int relayNumber, String name, bool status,
      IconData icon, Color color) {
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
                      color: status ? color.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
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
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(
                    status ? Icons.power_settings_new : Icons.power_settings_new,
                    color: status ? color : Colors.grey,
                    size: 32,
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
              setState(() => isControlling = true);

              // Turn off both relays
              await ApiService.controlRelay1(false);
              await ApiService.controlRelay2(false);

              setState(() {
                relay1Status = false;
                relay2Status = false;
                isControlling = false;
              });

              _showSuccessSnackBar("🚨 All devices shut down!");
            },
            child: Text("Yes, Stop All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
