import 'dart:convert';
import 'package:http/http.dart' as http;

class Esp32Service {
  static const String baseUrl = 'http://192.168.233.214:4000';

  static Future<Map<String, dynamic>?> fetchLatestData() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/esp32/latest'),
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('❌ ESP32 fetch error: $e');
    }
    return null;
  }
}
