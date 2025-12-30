import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NetworkConfig {
  static String esp32Ip = '192.168.137.226';
  static int esp32Port = 80;

  static String get esp32BaseUrl => 'http://$esp32Ip:$esp32Port';

  /// Fetches ESP32 IP and port from the server /api/config endpoint.
  /// Called once at app startup — all subsequent ESP32 calls use the loaded values.
  static Future<void> loadFromServer(String apiBaseUrl) async {
    try {
      final url = Uri.parse('$apiBaseUrl/config');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json'
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['esp32Ip'] != null) esp32Ip = data['esp32Ip'] as String;
        if (data['esp32Port'] != null) esp32Port = data['esp32Port'] as int;
        debugPrint('✅ NetworkConfig loaded: ESP32=$esp32Ip:$esp32Port');
      }
    } catch (e) {
      debugPrint(
          '⚠️ Could not load network config from server, using default: $e');
    }
  }
}
