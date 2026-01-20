import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MLService {
  static const String baseUrl = 'http://10.0.2.2:4000/api/ml';

  // Analyze energy data with ML
  static Future<Map<String, dynamic>> analyzeEnergy({
    required String userId,
    required List<double> powerData,
    required List<double> historicalData,
  }) async {
    try {
      debugPrint('📤 Sending energy analysis request...');

      final response = await http
          .post(
            Uri.parse('$baseUrl/analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'powerData': powerData,
              'historicalData': historicalData,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Analysis request timed out');
            },
          );

      debugPrint('📥 Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'analysis': data['analysis'],
          'anomalies': data['analysis']['anomalies'],
          'pattern': data['analysis']['pattern'],
          'suggestions': List<Map<String, dynamic>>.from(
            data['analysis']['suggestions'] ?? [],
          ),
        };
      } else {
        return {'success': false, 'error': 'Analysis failed'};
      }
    } catch (e) {
      debugPrint('❌ Analysis error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Detect anomalies only
  static Future<Map<String, dynamic>> detectAnomalies({
    required String userId,
    required List<double> powerData,
  }) async {
    try {
      debugPrint('🔍 Detecting anomalies...');

      final response = await http
          .post(
            Uri.parse('$baseUrl/detect-anomalies'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'powerData': powerData,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'detection': data['detection'],
          'isAnomaly': data['detection']['is_anomaly'] ?? false,
          'severity': data['detection']['severity'] ?? 0,
        };
      }
      return {'success': false};
    } catch (e) {
      debugPrint('❌ Detection error: $e');
      return {'success': false};
    }
  }

  // Get AI insights
  static Future<Map<String, dynamic>> getInsights(String userId) async {
    try {
      debugPrint('💡 Fetching AI insights...');

      final response = await http.get(
        Uri.parse('$baseUrl/insights/$userId'),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'insights': data['insights'],
        };
      }
      return {'success': false};
    } catch (e) {
      debugPrint('❌ Insights error: $e');
      return {'success': false};
    }
  }
}
