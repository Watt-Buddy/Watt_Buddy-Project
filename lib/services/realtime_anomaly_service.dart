import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'enhanced_notification_service.dart';

/// Real-time Anomaly Service using Socket.io
/// Listens for live anomaly alerts from the backend and triggers UI interactions
class RealtimeAnomalyService {
  static IO.Socket? _socket;
  static bool _isConnected = false;
  static Function? _onAnomalyAlert;
  static Function? _onRelayStatusChanged;

  // Cached device names for friendlier alerts
  static String? _relay1Name;
  static String? _relay2Name;

  /// Initialize Socket.io connection to backend
  static Future<void> initialize({
    required Function(Map<String, dynamic> data) onAnomalyAlert,
    required Function(Map<String, dynamic> data) onRelayStatusChanged,
  }) async {
    try {
      _onAnomalyAlert = onAnomalyAlert;
      _onRelayStatusChanged = onRelayStatusChanged;

      // Connect to backend server (Socket.io uses http:// not ws://)
      final baseUrl = ApiService.baseUrl.replaceFirst('/api', '');
      _socket = IO.io(
        baseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableForceNew()
            .build(),
      );

      _socket!.onConnect((_) {
        _isConnected = true;
        debugPrint('✅ Socket.io Connected: ${_socket!.id}');
      });

      // 🚨 Listen for Anomaly Alerts
      _socket!.on('anomaly_alert', (data) async {
        try {
          debugPrint('🚨 Anomaly Alert Received: $data');
          if (data is! Map) return;

          final payload = Map<String, dynamic>.from(data);
          if (_onAnomalyAlert != null) {
            // Keep UI updates independent from notification side-effects.
            try {
              _onAnomalyAlert!(payload);
            } catch (e) {
              debugPrint('⚠️ Failed to run anomaly UI callback: $e');
            }
          }

          try {
            await _handleAnomalyAlert(payload);
          } catch (e) {
            debugPrint('⚠️ Failed to process anomaly side-effects: $e');
          }
        } catch (e) {
          debugPrint('❌ Failed to handle anomaly_alert payload: $e');
        }
      });

      // 🔌 Listen for Relay Status Updates
      _socket!.on('relay_status', (data) {
        try {
          debugPrint('🔌 Relay Status Update: $data');
          if (data is! Map) return;
          final payload = Map<String, dynamic>.from(data);

          if (_onRelayStatusChanged != null) {
            _onRelayStatusChanged!(payload);
          }
        } catch (e) {
          debugPrint('❌ Failed to handle relay_status payload: $e');
        }
      });

      // 📡 Listen for Live Data Updates
      _socket!.on('live_data_update', (data) {
        try {
          if (data is! Map) return;
          final payload = Map<String, dynamic>.from(data);
          debugPrint('📡 Live Data Update: Power=${payload['power']}W');
        } catch (e) {
          debugPrint('❌ Failed to handle live_data_update payload: $e');
        }
      });

      _socket!.onDisconnect((_) {
        _isConnected = false;
        debugPrint('🔌 Socket.io Disconnected');
      });

      _socket!.onError((error) {
        debugPrint('❌ Socket.io Error: $error');
      });
    } catch (e) {
      debugPrint('❌ Error initializing Socket.io: $e');
    }
  }

  /// Internal handler for anomaly alerts
  static Future<void> _handleAnomalyAlert(Map<String, dynamic> data) async {
    final isAbnormal = data['isAbnormal'] as bool? ?? false;
    if (!isAbnormal) return;

    final anomalySocket = data['anomalySocket'] as String? ?? 'Unknown';
    final currentPower = (data['currentPower'] as num?) ?? 0;
    final message = data['message'] as String? ?? 'High power usage detected';
    final dominantRelay = (data['dominantRelay'] as num?)?.toInt() ?? 0;
    final dominantPower = (data['dominantPower'] as num?)?.toDouble() ?? 0.0;

    // Load friendly device names from SharedPreferences once
    if (_relay1Name == null || _relay2Name == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _relay1Name = prefs.getString('relay1_name') ?? 'Device 1';
        _relay2Name = prefs.getString('relay2_name') ?? 'Device 2';
      } catch (e) {
        debugPrint('⚠️ Failed to load relay names: $e');
        _relay1Name ??= 'Device 1';
        _relay2Name ??= 'Device 2';
      }
    }

    String deviceName = anomalySocket;
    if (dominantRelay == 1) deviceName = _relay1Name ?? 'Device 1';
    if (dominantRelay == 2) deviceName = _relay2Name ?? 'Device 2';

    // Build two-level alert message: generic anomaly + device-specific hint
    String body = message;
    if (dominantRelay != 0 && dominantPower > 0) {
      body =
          '$message\nLikely source: $deviceName (~${dominantPower.toStringAsFixed(0)}W)';
    }

    await EnhancedNotificationService.sendAnomalyAlert(
      title: dominantRelay != 0
          ? '⚠️ Possible Faulty Device: $deviceName'
          : '⚠️ Power Spike Alert!',
      body: body,
      anomalyType: dominantRelay != 0 ? 'DeviceFault' : 'HighPowerUsage',
      power: currentPower.toDouble(),
    );

    debugPrint(
        '🚨 Anomaly: $anomalySocket using ${currentPower}W, dominantRelay=$dominantRelay, dominantPower=$dominantPower');
  }

  /// Turn off a specific socket (Socket 1 or Socket 2)
  static Future<bool> turnOffSocket(String socketName) async {
    try {
      final socketNum = socketName.contains('1') ? '1' : '2';

      // Call ESP32 directly to turn off the relay
      bool success = false;
      if (socketNum == '1') {
        success = await ApiService.controlESP32Relay1Off();
      } else {
        success = await ApiService.controlESP32Relay2Off();
      }

      if (success) {
        debugPrint('✅ Socket $socketNum relay turned OFF via ESP32');

        // Send confirmation notification
        await EnhancedNotificationService.sendRelayStatusNotification(
          isOn: false,
          reason: 'User disabled due to high power usage',
        );

        return true;
      }

      debugPrint('❌ Failed to turn off socket $socketNum');
      return false;
    } catch (e) {
      debugPrint('❌ Error turning off socket: $e');
      return false;
    }
  }

  /// Turn on a specific socket
  static Future<bool> turnOnSocket(String socketName) async {
    try {
      final socketNum = socketName.contains('1') ? '1' : '2';

      // Call ESP32 directly to turn on the relay
      bool success = false;
      if (socketNum == '1') {
        success = await ApiService.controlESP32Relay1On();
      } else {
        success = await ApiService.controlESP32Relay2On();
      }

      if (success) {
        debugPrint('🟢 Socket $socketNum relay turned ON via ESP32');

        await EnhancedNotificationService.sendRelayStatusNotification(
          isOn: true,
          reason: 'User re-enabled socket',
        );

        return true;
      }

      debugPrint('❌ Failed to turn on socket $socketNum');
      return false;
    } catch (e) {
      debugPrint('❌ Error turning on socket: $e');
      return false;
    }
  }

  /// Get relay status from server
  static Future<Map<String, dynamic>> getRelayStatus() async {
    try {
      final response = await ApiService.get('/relay/status');
      return {
        'relay1': response['relay1'] as int? ?? 0,
        'relay2': response['relay2'] as int? ?? 0,
        'timestamp': response['timestamp'] as String? ?? '',
      };
    } catch (e) {
      debugPrint('❌ Error getting relay status: $e');
      return {'relay1': 0, 'relay2': 0, 'timestamp': ''};
    }
  }

  /// Check if Socket.io is connected
  static bool get isConnected => _isConnected;

  /// Disconnect Socket.io
  static void disconnect() {
    _socket?.disconnect();
    _isConnected = false;
    debugPrint('🔌 Socket.io disconnected');
  }

  /// Reconnect Socket.io
  static void reconnect() {
    if (_socket != null && !_isConnected) {
      _socket!.connect();
    }
  }

  /// Get socket ID
  static String? get socketId => _socket?.id;
}
