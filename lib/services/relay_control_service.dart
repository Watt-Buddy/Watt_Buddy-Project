import 'api_service.dart';
import 'anomaly_notification_service.dart';

class RelayControlService {
  // Control relay on/off
  static Future<bool> controlRelay({
    required String userId,
    required bool turnOn,
    String reason = 'User requested',
  }) async {
    try {
      final endpoint = turnOn ? '/relay/on' : '/relay/off';

      final response = await ApiService.post(
        endpoint,
        {'userId': userId, 'reason': reason},
      );

      if (response['success'] == true) {
        // Send notification about relay status
        await AnomalyNotificationService.sendRelayControlNotification(
          isOn: turnOn,
          reason: reason,
        );

        print('${turnOn ? '✅' : '⚫'} Relay ${turnOn ? 'turned ON' : 'turned OFF'}');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Error controlling relay: $e');
      throw Exception('Failed to control relay: $e');
    }
  }

  // Get current relay status
  static Future<bool> getRelayStatus(String userId) async {
    try {
      final response = await ApiService.get('/relay/status/$userId');

      if (response['success'] == true) {
        return response['relayState'] == true;
      }

      return false;
    } catch (e) {
      print('❌ Error getting relay status: $e');
      throw Exception('Failed to get relay status: $e');
    }
  }

  // Auto-cut relay on anomaly
  static Future<bool> autoDisableOnAnomaly({
    required String userId,
    required String anomalyType,
  }) async {
    try {
      return await controlRelay(
        userId: userId,
        turnOn: false,
        reason: 'Auto-disabled due to: $anomalyType',
      );
    } catch (e) {
      print('❌ Error auto-disabling relay: $e');
      return false;
    }
  }

  // Toggle relay
  static Future<bool> toggleRelay(String userId) async {
    try {
      final currentState = await getRelayStatus(userId);
      return await controlRelay(
        userId: userId,
        turnOn: !currentState,
        reason: 'User toggled relay',
      );
    } catch (e) {
      print('❌ Error toggling relay: $e');
      throw Exception('Failed to toggle relay: $e');
    }
  }

  // Set relay with schedule
  static Future<bool> setRelaySchedule({
    required String userId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      final response = await ApiService.post(
        '/relay/schedule',
        {
          'userId': userId,
          'startTime': startTime.toIso8601String(),
          'endTime': endTime.toIso8601String(),
        },
      );

      if (response['success'] == true) {
        print('✅ Relay schedule set from ${startTime.hour}:${startTime.minute} to ${endTime.hour}:${endTime.minute}');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Error setting relay schedule: $e');
      throw Exception('Failed to set relay schedule: $e');
    }
  }

  // Get relay history
  static Future<List<Map<String, dynamic>>?> getRelayHistory({
    required String userId,
    int limit = 50,
  }) async {
    try {
      final response = await ApiService.get(
        '/relay/history/$userId?limit=$limit',
      );

      if (response['success'] == true && response['history'] != null) {
        return List<Map<String, dynamic>>.from(response['history']);
      }

      return null;
    } catch (e) {
      print('❌ Error getting relay history: $e');
      return null;
    }
  }

  // Monitor relay health
  static Future<Map<String, dynamic>?> getRelayHealth(String userId) async {
    try {
      final response = await ApiService.get('/relay/health/$userId');

      if (response['success'] == true) {
        return {
          'switchCount': response['totalSwitches'] ?? 0,
          'health': response['health'] ?? 'good',
          'expectedLifespan': response['expectedLifespan'] ?? 'normal',
          'lastMaintenance': response['lastMaintenance'],
        };
      }

      return null;
    } catch (e) {
      print('❌ Error getting relay health: $e');
      return null;
    }
  }
}
