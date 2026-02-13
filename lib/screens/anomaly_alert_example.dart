import 'package:flutter/material.dart';
import '../services/realtime_anomaly_service.dart';

/// Example Integration of Realtime Anomaly Alert System
/// Add this code to your Bill Prediction Screen or Dashboard
class AnomalyAlertIntegrationExample extends StatefulWidget {
  const AnomalyAlertIntegrationExample({super.key});

  @override
  State<AnomalyAlertIntegrationExample> createState() =>
      _AnomalyAlertIntegrationExampleState();
}

class _AnomalyAlertIntegrationExampleState
    extends State<AnomalyAlertIntegrationExample> {
  bool _isConnected = false;
  Map<String, dynamic> _lastAnomalyData = {};
  Map<String, dynamic> _relayStatus = {'relay1': 0, 'relay2': 0};

  @override
  void initState() {
    super.initState();
    _initializeAnomalyService();
    _checkRelayStatus();
  }

  /// Initialize real-time anomaly service
  Future<void> _initializeAnomalyService() async {
    await RealtimeAnomalyService.initialize(
      // Called when anomaly is detected
      onAnomalyAlert: (data) {
        setState(() {
          _lastAnomalyData = data;
          _isConnected = RealtimeAnomalyService.isConnected;
        });

        // Show interactive alert dialog
        _showAnomalyAlertDialog(
          socketName: data['anomalySocket'] ?? 'Unknown',
          power: data['currentPower'] ?? 0,
          message: data['message'] ?? 'High power usage detected',
        );
      },

      // Called when relay status changes
      onRelayStatusChanged: (data) {
        setState(() {
          _relayStatus = {
            'relay': data['relay'],
            'status': data['status'],
            'timestamp': data['timestamp'],
          };
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message'] ?? 'Relay status updated',
            ),
            backgroundColor: data['status'] == 'on'
                ? Colors.green
                : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      },
    );

    setState(() {
      _isConnected = RealtimeAnomalyService.isConnected;
    });
  }

  /// Interactive Alert Dialog
  void _showAnomalyAlertDialog({
    required String socketName,
    required num power,
    required String message,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false, // Force user action
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title with warning icon
              Row(
                children: [
                  const Text(
                    '⚠️ ',
                    style: TextStyle(fontSize: 32),
                  ),
                  Expanded(
                    child: Text(
                      'Power Spike Alert',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Alert message
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),

              // Power usage box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  border: Border.all(color: Colors.red.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt,
                      color: Colors.amber.shade600,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Power Usage',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          '${power.toStringAsFixed(0)} W',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Socket info
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.outlet,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      socketName,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Alert dismissed. Monitor the device.',
                            ),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'NEGLECT',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _turnOffSocket(socketName);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'TURN OFF',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Turn off socket and show status
  Future<void> _turnOffSocket(String socketName) async {
    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Disconnecting $socketName...'),
        duration: const Duration(seconds: 2),
      ),
    );

    final success = await RealtimeAnomalyService.turnOffSocket(socketName);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ $socketName has been safely disconnected',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ Failed to turn off $socketName',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Check relay status from server
  Future<void> _checkRelayStatus() async {
    final status = await RealtimeAnomalyService.getRelayStatus();
    setState(() {
      _relayStatus = status;
    });
  }

  /// Manually test anomaly alert (for demo purposes)
  void _testAnomalyAlert() {
    _showAnomalyAlertDialog(
      socketName: 'Socket 1',
      power: 2850,
      message: '⚠️ Socket 1 is using abnormal power! (2850W)',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A2A),
      appBar: AppBar(
        title: const Text('Anomaly Alert System'),
        backgroundColor: const Color(0xFF1A1A3A),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection Status Card
          Card(
            color: const Color(0xFF1A1A3A),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isConnected ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Socket.io Connection',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        _isConnected
                            ? 'Connected'
                            : 'Disconnected (Reconnecting...)',
                        style: TextStyle(
                          color: _isConnected ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (RealtimeAnomalyService.socketId != null)
                    Text(
                      RealtimeAnomalyService.socketId!.substring(0, 8),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Relay Status Card
          Card(
            color: const Color(0xFF1A1A3A),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Relay Status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _RelayStatusWidget(
                        socket: 'Socket 1',
                        isActive: (_relayStatus['relay1'] as int?) == 1,
                      ),
                      _RelayStatusWidget(
                        socket: 'Socket 2',
                        isActive: (_relayStatus['relay2'] as int?) == 1,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Last Anomaly Card
          if (_lastAnomalyData.isNotEmpty)
            Card(
              color: Colors.red.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last Anomaly Alert',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.orange,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _lastAnomalyData['anomalySocket'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_lastAnomalyData['currentPower']}W',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Demo Button
          ElevatedButton.icon(
            onPressed: _testAnomalyAlert,
            icon: const Icon(Icons.warning),
            label: const Text('Test Alert Dialog'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    RealtimeAnomalyService.disconnect();
    super.dispose();
  }
}

/// Widget to display relay status
class _RelayStatusWidget extends StatelessWidget {
  final String socket;
  final bool isActive;

  const _RelayStatusWidget({
    required this.socket,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: isActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? Colors.green : Colors.red,
              width: 2,
            ),
          ),
          child: Icon(
            Icons.outlet,
            color: isActive ? Colors.green : Colors.red,
            size: 32,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          socket,
          style: const TextStyle(fontSize: 12),
        ),
        Text(
          isActive ? 'ON' : 'OFF',
          style: TextStyle(
            color: isActive ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
