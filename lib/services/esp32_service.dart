import 'dart:convert';
import 'package:http/http.dart' as http;

class Esp32Service {
  // Match backend PC IP from ipconfig (IPv4 Address: 10.148.3.49)
  static const String baseUrl = 'http://10.148.3.49:4000';

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
