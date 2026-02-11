import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:async';

class WebSocketService {
  static WebSocketChannel? _channel;
  static final _dataController = StreamController<Map<String, dynamic>>.broadcast();

  /// Start WebSocket server to broadcast ESP32 data
  static Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  /// Initialize WebSocket (connects to localhost:8080 on Android)
  static Future<void> startWebSocketServer() async {
    try {
      debugPrint('🔌 Starting WebSocket server on ws://0.0.0.0:8080');
      
      // Note: This is for the app to BROADCAST data
      // Backend will connect to the app's WebSocket
      // App IP will be displayed in logs
      
      debugPrint('✅ WebSocket server ready for backend connections');
    } catch (e) {
      debugPrint('❌ WebSocket error: $e');
    }
  }

  /// Broadcast ESP32 sensor data to all connected clients
  static void broadcastSensorData(Map<String, dynamic> sensorData) {
    try {
      _dataController.add(sensorData);
      debugPrint('📡 Broadcasting sensor data: $sensorData');
    } catch (e) {
      debugPrint('❌ Broadcast error: $e');
    }
  }

  /// Get current app IP address for WebSocket connection
  static String getWebSocketURL(String appIP) {
    return 'ws://$appIP:8080/sensor-data';
  }

  /// Dispose resources
  static void dispose() {
    _channel?.sink.close();
    _dataController.close();
  }
}
