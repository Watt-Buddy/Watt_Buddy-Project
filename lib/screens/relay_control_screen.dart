import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';

class RelayControlScreen extends StatefulWidget {
  const RelayControlScreen({Key? key}) : super(key: key);

  @override
  State<RelayControlScreen> createState() => _RelayControlScreenState();
}

class _RelayControlScreenState extends State<RelayControlScreen> {
  bool _relayState = false;
  bool _isLoading = false;
  String? _userId;
  Map<String, dynamic>? _sensorData;

  @override
  void initState() {
    super.initState();
    _loadUserAndSensorData();
  }

  Future<void> _loadUserAndSensorData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('wattBuddyUser');
    
    if (userJson != null) {
      final user = jsonDecode(userJson);
      setState(() => _userId = user['id'].toString());
      _fetchSensorData();
      _fetchRelayStatus();
    }
  }

  Future<void> _fetchSensorData() async {
    try {
      // This would need an endpoint on your ESP32
      // For now, we'll fetch from the server
      final data = await ApiService.get('/esp32/sensors/$_userId');
      setState(() => _sensorData = data);
    } catch (e) {
      debugPrint('Error fetching sensor data: $e');
    }
  }

  Future<void> _fetchRelayStatus() async {
    try {
      final data = await ApiService.get('/relay/status/$_userId');
      if (mounted) {
        setState(() => _relayState = data['relayState'] ?? false);
      }
    } catch (e) {
      debugPrint('Error fetching relay status: $e');
    }
  }

  Future<void> _toggleRelay() async {
    setState(() => _isLoading = true);

    try {
      final newState = !_relayState;
      final endpoint = newState ? '/relay/on' : '/relay/off';
      
      await ApiService.post(endpoint, {'userId': _userId});

      if (mounted) {
        setState(() => _relayState = newState);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Relay turned ${newState ? 'ON' : 'OFF'} successfully',
            ),
            backgroundColor: newState ? Colors.green : Colors.orange,
          ),
        );
      }

      _fetchSensorData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡ Power Control'),
        backgroundColor: Colors.blue.shade800,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Main Relay Control Card
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _relayState
                        ? [Colors.green.shade400, Colors.green.shade700]
                        : [Colors.grey.shade400, Colors.grey.shade700],
                  ),
                ),
                child: Column(
                  children: [
                    // Power Icon Animation
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: _relayState ? 1 : 0,
                      ),
                      duration: const Duration(milliseconds: 500),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: 0.5 + (value * 0.5),
                          child: Icon(
                            Icons.flash_on,
                            size: 100,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // Status Text
                    Text(
                      _relayState ? 'POWER ON' : 'POWER OFF',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Status Description
                    Text(
                      _relayState
                          ? 'Current is flowing'
                          : 'Current is cut off',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Toggle Button
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _toggleRelay,
                      icon: Icon(
                        _relayState ? Icons.power_settings_new : Icons.power,
                      ),
                      label: Text(
                        _isLoading
                            ? 'Processing...'
                            : _relayState
                                ? 'Turn OFF'
                                : 'Turn ON',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor:
                            _relayState ? Colors.red : Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Real-time Sensor Data
            if (_sensorData != null) ...[
              Text(
                'Real-time Readings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 15),
              SensorDataGrid(sensorData: _sensorData!),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(20),
                child: const CircularProgressIndicator(),
              ),
            ],

            const SizedBox(height: 30),

            // Safety Information
            Card(
              color: Colors.orange.shade100,
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning,
                          color: Colors.orange.shade800,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Safety Information',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '• Anomalies will auto-cut off the power\n'
                      '• Check sensor readings before turning on\n'
                      '• Keep this app updated for best performance',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sensor Data Grid Widget
class SensorDataGrid extends StatelessWidget {
  final Map<String, dynamic> sensorData;

  const SensorDataGrid({
    Key? key,
    required this.sensorData,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final sensors = [
      SensorInfo(
        label: 'Voltage',
        value: '${(sensorData['voltage'] ?? 0).toStringAsFixed(1)}V',
        icon: Icons.flash_on,
        color: Colors.blue,
      ),
      SensorInfo(
        label: 'Current',
        value: '${(sensorData['current'] ?? 0).toStringAsFixed(2)}A',
        icon: Icons.electrical_services,
        color: Colors.red,
      ),
      SensorInfo(
        label: 'Power',
        value: '${(sensorData['power'] ?? 0).toStringAsFixed(0)}W',
        icon: Icons.bolt,
        color: Colors.amber,
      ),
      SensorInfo(
        label: 'Frequency',
        value: '${(sensorData['frequency'] ?? 50)}Hz',
        icon: Icons.waves,
        color: Colors.purple,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 15,
      crossAxisSpacing: 15,
      children: sensors
          .map(
            (sensor) => SensorCard(sensor: sensor),
          )
          .toList(),
    );
  }
}

class SensorInfo {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  SensorInfo({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class SensorCard extends StatelessWidget {
  final SensorInfo sensor;

  const SensorCard({
    super.key,
    required this.sensor,
  }) : super();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              sensor.color.withValues(alpha: 0.3),
              sensor.color.withValues(alpha: 0.1),
            ],
          ),
        ),
        padding: const EdgeInsets.all(15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              sensor.icon,
              color: sensor.color,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              sensor.value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: sensor.color,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              sensor.label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
