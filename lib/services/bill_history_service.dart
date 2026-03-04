import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class BillHistoryService {
  /// Fetches past bill records for a user.
  /// The backend currently returns a list of maps with keys:
  /// period, dueDate, amount, units, status.
  static Future<List<Map<String, dynamic>>> getHistory(String userId) async {
    try {
      debugPrint('📤 Fetching bill history for user $userId');
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/billing/history/$userId'))
          .timeout(ApiService.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['bills'] != null) {
          return List<Map<String, dynamic>>.from(data['bills']);
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ Error fetching bill history: $e');
      return [];
    }
  }
}
