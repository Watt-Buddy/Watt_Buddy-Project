import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MonthlyUsageService {
  static const String baseUrl = 'http://10.0.2.2:4000/api/usage';

  // Update daily usage
  static Future<Map<String, dynamic>> updateDailyUsage({
    required String userId,
    required double dailyKwh,
    String? usageDate,
  }) async {
    try {
      debugPrint('📤 Updating daily usage...');

      final response = await http
          .post(
            Uri.parse('$baseUrl/daily-usage'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'dailyKwh': dailyKwh,
              'usageDate': usageDate,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }
      return {'success': false};
    } catch (e) {
      debugPrint('❌ Error updating daily usage: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Get monthly usage summary
  static Future<Map<String, dynamic>> getMonthlyUsageSummary({
    required String userId,
    String? monthYear,
  }) async {
    try {
      debugPrint('📤 Fetching monthly usage summary...');

      final uri = Uri.parse('$baseUrl/monthly-summary/$userId');
      final response = await http
          .get(
            monthYear != null ? uri.replace(queryParameters: {'monthYear': monthYear}) : uri,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'summary': data['summary'],
        };
      }
      return {'success': false};
    } catch (e) {
      debugPrint('❌ Error fetching monthly summary: $e');
      return {'success': false};
    }
  }

  // Get monthly limit
  static Future<double> getMonthlyLimit(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/monthly-limit/$userId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['monthlyLimit'] ?? 300).toDouble();
      }
      return 300.0;
    } catch (e) {
      debugPrint('❌ Error fetching monthly limit: $e');
      return 300.0;
    }
  }

  // Set monthly limit
  static Future<bool> setMonthlyLimit({
    required String userId,
    required double limitKwh,
  }) async {
    try {
      debugPrint('📤 Setting monthly limit: $limitKwh kWh');

      final response = await http
          .post(
            Uri.parse('$baseUrl/monthly-limit'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'limitKwh': limitKwh,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error setting monthly limit: $e');
      return false;
    }
  }

  // Get usage forecast
  static Future<Map<String, dynamic>> getUsageForecast(String userId) async {
    try {
      debugPrint('📤 Fetching usage forecast...');

      final response = await http
          .get(Uri.parse('$baseUrl/forecast/$userId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'forecast': data['forecast'],
        };
      }
      return {'success': false};
    } catch (e) {
      debugPrint('❌ Error fetching forecast: $e');
      return {'success': false};
    }
  }

  // Get usage alerts
  static Future<List<Map<String, dynamic>>> getUsageAlerts(String userId) async {
    try {
      debugPrint('📤 Fetching usage alerts...');

      final response = await http
          .get(Uri.parse('$baseUrl/alerts/$userId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final alerts = data['alerts'] as List?;
        return List<Map<String, dynamic>>.from(alerts ?? []);
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error fetching alerts: $e');
      return [];
    }
  }

  // Resolve alert
  static Future<bool> resolveAlert(int alertId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/alerts/resolve'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'alertId': alertId}),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error resolving alert: $e');
      return false;
    }
  }

  // Get daily usage stats
  static Future<Map<String, dynamic>> getDailyUsageStats({
    required String userId,
    int days = 30,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/daily-stats/$userId?days=$days'),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'stats': data['stats'],
        };
      }
      return {'success': false};
    } catch (e) {
      debugPrint('❌ Error fetching daily stats: $e');
      return {'success': false};
    }
  }
}
