import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use emulator host so Android emulator can reach the local server
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:4000/api';
    }

    if (Platform.isAndroid) {
      // REAL ANDROID PHONE (CPH2001)
      return 'http://172.17.4.170:4000/api';
    }

    // Windows / macOS / Linux
    return 'http://localhost:4000/api';
  }

  // For a real phone on the same Wi-Fi use: http://YOUR_PC_IP:4000/api

  // Connection timeout - increase from 10 to 30 seconds to allow for database operations
  static const Duration connectionTimeout = Duration(seconds: 30);

  // ============ GENERIC HTTP METHODS ============
  /// Generic POST request
  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      debugPrint('📤 POST $endpoint: $body');
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(connectionTimeout);

      debugPrint('📥 Response: ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('❌ POST Error: $e');
      throw Exception('POST $endpoint failed: $e');
    }
  }

  /// Generic GET request
  static Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      debugPrint('📤 GET $endpoint');
      final response = await http
          .get(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(connectionTimeout);
      debugPrint('📥 Response: ${response.statusCode}');
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('❌ GET Error: $e');
      throw Exception('GET $endpoint failed: $e');
    }
  }

  // ---------------- REGISTER ----------------
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String consumerNumber,
    required String password,
  }) async {
    try {
      debugPrint('📤 Registering user: $email');
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'email': email,
              'consumer_number': consumerNumber,
              'password': password,
            }),
          )
          .timeout(
            connectionTimeout,
            onTimeout: () {
              throw Exception('Registration request timed out. Make sure the server is running and the database is accessible.');
            },
          );

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        return {
          'message': errorData['message'] ?? 'Registration failed',
          'success': false,
        };
      }
    } on SocketException catch (e) {
      debugPrint('❌ Network error: $e');
      return {
        'message': 'Cannot reach server. Is the backend running on http://10.0.2.2:4000?',
        'success': false,
      };
    }
  }

  // ---------------- LOGIN ----------------
  static Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('📤 Logging in: $email');
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(
            connectionTimeout,
            onTimeout: () {
              throw Exception('Login request timed out. Make sure the server is running and the database is accessible.');
            },
          );

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('wattBuddyUser', jsonEncode(data['user']));
        debugPrint('✅ Login successful');
        return true;
      }

      debugPrint('❌ Login failed: ${data['message']}');
      return false;
    } on SocketException catch (e) {
      debugPrint('❌ Network error: $e');
      return false;
    }
  }

  // ============ RELAY CONTROL ============
  static Future<bool> controlRelay1(bool turnOn) async {
    try {
      final endpoint = turnOn ? '/relay1/on' : '/relay1/off';
      debugPrint('📤 Sending relay 1 command: ${turnOn ? 'ON' : 'OFF'}');
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Relay 1 ${turnOn ? 'ON' : 'OFF'} successful');
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Relay 1 control error: $e');
      return false;
    }
  }

  static Future<bool> controlRelay2(bool turnOn) async {
    try {
      final endpoint = turnOn ? '/relay2/on' : '/relay2/off';
      debugPrint('📤 Sending relay 2 command: ${turnOn ? 'ON' : 'OFF'}');
      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Relay 2 ${turnOn ? 'ON' : 'OFF'} successful');
        return data['success'] ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Relay 2 control error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getRelayStatus() async {
    try {
      debugPrint('📤 Getting relay status');
      final response = await http
          .get(
            Uri.parse('$baseUrl/relay/all'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Got relay status: $data');
        return data;
      }
      return {};
    } catch (e) {
      debugPrint('❌ Get relay status error: $e');
      return {};
    }
  }

  // ============ ESP32 SENSOR ENDPOINTS ============
  
  /// Get current sensor readings from ESP32
  /// Reads: Voltage, Current, Power, Daily/Monthly Energy
  static Future<Map<String, dynamic>> getESP32Sensors() async {
    try {
      debugPrint('📊 Fetching ESP32 sensor readings...');
      
      // Direct connection to ESP32 (local network)
      const String esp32Url = 'http://10.168.130.214:80/sensors';
      
      final response = await http
          .get(
            Uri.parse(esp32Url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ ESP32 Sensors: $data');
        return {
          'success': true,
          'voltage': data['voltage'] ?? 0.0,
          'current': data['current'] ?? 0.0,
          'power': data['power'] ?? 0.0,
          'relay': data['relay'] ?? false,
          'totalEnergy': data['totalEnergy'] ?? 0.0,
          'dailyEnergy': data['dailyEnergy'] ?? 0.0,
          'monthlyEnergy': data['monthlyEnergy'] ?? 0.0,
          'timestamp': data['timestamp'] ?? 0,
        };
      }
      return {'success': false, 'error': 'ESP32 not responding'};
    } catch (e) {
      debugPrint('❌ ESP32 sensor error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Control ESP32 relay ON
  static Future<bool> turnESP32RelayOn() async {
    try {
      debugPrint('🔌 Turning ESP32 relay ON...');
      const String esp32Url = 'http://10.168.130.214:80/relay/on';
      
      final response = await http
          .post(
            Uri.parse(esp32Url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('✅ Relay turned ON');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Relay ON error: $e');
      return false;
    }
  }

  /// Control ESP32 relay OFF
  static Future<bool> turnESP32RelayOff() async {
    try {
      debugPrint('🔌 Turning ESP32 relay OFF...');
      const String esp32Url = 'http://10.168.130.214:80/relay/off';
      
      final response = await http
          .post(
            Uri.parse(esp32Url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('✅ Relay turned OFF');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Relay OFF error: $e');
      return false;
    }
  }

  /// Get ESP32 relay status
  static Future<Map<String, dynamic>> getESP32RelayStatus() async {
    try {
      debugPrint('📊 Fetching ESP32 relay status...');
      const String esp32Url = 'http://10.168.130.214:80/relay/status';
      
      final response = await http
          .get(
            Uri.parse(esp32Url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'relay': data['relay'] ?? false,
          'voltage': data['voltage'] ?? 0.0,
          'current': data['current'] ?? 0.0,
          'power': data['power'] ?? 0.0,
        };
      }
      return {'success': false};
    } catch (e) {
      debugPrint('❌ ESP32 relay status error: $e');
      return {'success': false};
    }
  }

  /// Set logged-in user on ESP32
  static Future<bool> setESP32User(String userId) async {
    try {
      debugPrint('👤 Setting ESP32 user: $userId');
      final String esp32Url = 'http://10.168.130.214:80/user/set?userId=$userId';
      
      final response = await http
          .post(
            Uri.parse(esp32Url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('✅ ESP32 user set to: $userId');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Set ESP32 user error: $e');
      return false;
    }
  }

  /// Get energy data from ESP32
  static Future<Map<String, dynamic>> getESP32Energy() async {
    try {
      debugPrint('⚡ Fetching ESP32 energy data...');
      const String esp32Url = 'http://10.168.130.214:80/energy';
      
      final response = await http
          .get(
            Uri.parse(esp32Url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'totalEnergy': data['totalEnergy'] ?? 0.0,
          'dailyEnergy': data['dailyEnergy'] ?? 0.0,
          'monthlyEnergy': data['monthlyEnergy'] ?? 0.0,
        };
      }
      return {'success': false};
    } catch (e) {
      debugPrint('❌ ESP32 energy error: $e');
      return {'success': false};
    }
  }

}

