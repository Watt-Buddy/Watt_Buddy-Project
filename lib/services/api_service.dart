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

}
