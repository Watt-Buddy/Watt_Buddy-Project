import 'api_service.dart';

class ESP32StorageService {
  // 🗄 Store ESP32 reading in PostgreSQL
  static Future<bool> storeReading({
    required String userId,
    required double power,
    required double voltage,
    required double current,
    required double energy,
    required double pf,
    required double frequency,
    required double temperature,
  }) async {
    try {
      final data = await ApiService.post(
        '/esp32/data',
        {
          'userId': userId,
          'power': power,
          'voltage': voltage,
          'current': current,
          'energy': energy,
          'pf': pf,
          'frequency': frequency,
          'temperature': temperature,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      print('✅ ESP32 data stored successfully');
      return data['success'] == true;
    } catch (e) {
      print('❌ Error storing ESP32 data: $e');
      return false;
    }
  }

  // Get latest stored readings
  static Future<List<Map<String, dynamic>>?> getLatestReadings(
    String userId, {
    int limit = 100,
  }) async {
    try {
      final data = await ApiService.get(
        '/esp32/latest/$userId?limit=$limit',
      );

      if (data['success'] == true && data['readings'] != null) {
        return List<Map<String, dynamic>>.from(data['readings']);
      }
      return null;
    } catch (e) {
      print('❌ Error fetching readings: $e');
      return null;
    }
  }

  // Get daily stats
  static Future<Map<String, dynamic>?> getDailyStats(
    String userId, {
    String? date,
  }) async {
    try {
      final dateParam = date ?? DateTime.now().toString().split(' ')[0];
      final data = await ApiService.get(
        '/esp32/stats/$userId?date=$dateParam',
      );

      if (data['success'] == true && data['stats'] != null) {
        return Map<String, dynamic>.from(data['stats']);
      }
      return null;
    } catch (e) {
      print('❌ Error fetching daily stats: $e');
      return null;
    }
  }

  // Get hourly statistics
  static Future<List<Map<String, dynamic>>?> getHourlyStats(
    String userId, {
    String? date,
  }) async {
    try {
      final dateParam = date ?? DateTime.now().toString().split(' ')[0];
      final data = await ApiService.get(
        '/esp32/hourly/$userId?date=$dateParam',
      );

      if (data['success'] == true && data['hourly'] != null) {
        return List<Map<String, dynamic>>.from(data['hourly']);
      }
      return null;
    } catch (e) {
      print('❌ Error fetching hourly stats: $e');
      return null;
    }
  }
}
