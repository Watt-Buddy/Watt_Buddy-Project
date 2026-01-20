import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

class PowerLimitNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);
  }

  // 🔔 Send power limit notification
  static Future<void> showPowerLimitNotification({
    required String title,
    required String body,
    required double currentPower,
    required double powerLimit,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'power_limit_channel',
      'Power Limit Alerts',
      channelDescription: 'Alerts when power usage exceeds limits',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
    );
  }

  // Check power limit and notify
  static Future<void> checkAndNotifyPowerLimit(
    String userId,
    double currentPower,
    double powerLimit,
  ) async {
    try {
      final data = await ApiService.post(
        '/power-limit/check',
        {
          'userId': userId,
          'currentUsage': currentPower,
          'dailyLimit': powerLimit,
        },
      );

      if (data['notificationSent'] == true) {
        final percentage = data['percentage'] ?? 0.0;
        final threshold = data['threshold'] ?? 0;

        await showPowerLimitNotification(
          title: threshold == 100
              ? '🚨 Power Limit Exceeded!'
              : '⚠️ Power Usage Warning',
          body:
              'Your power usage is at ${percentage.toStringAsFixed(1)}% of daily limit',
          currentPower: currentPower,
          powerLimit: powerLimit,
        );
      }
    } catch (e) {
      print('❌ Error checking power limit: $e');
    }
  }

  // Set power limit
  static Future<bool> setPowerLimit(
    String userId,
    double dailyLimit,
  ) async {
    try {
      final data = await ApiService.post(
        '/power-limit/set',
        {
          'userId': userId,
          'dailyLimit': dailyLimit,
        },
      );

      return data['success'] == true;
    } catch (e) {
      print('❌ Error setting power limit: $e');
      return false;
    }
  }

  // Get power limit settings
  static Future<Map<String, dynamic>?> getPowerLimitSettings(
    String userId,
  ) async {
    try {
      final data = await ApiService.get(
        '/power-limit/$userId',
      );

      if (data['success'] == true) {
        return {
          'daily_power_limit': data['daily_power_limit'] ?? 5000.0,
          'alert_threshold': data['alert_threshold'] ?? 0.75,
        };
      }
      return null;
    } catch (e) {
      print('❌ Error fetching power limit settings: $e');
      return null;
    }
  }
}
