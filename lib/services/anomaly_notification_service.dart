import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

class AnomalyNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Notification IDs
  static const int anomalyAlertId = 1001;
  static const int overvoltageAlertId = 1002;
  static const int overcurrentAlertId = 1003;
  static const int overpowerAlertId = 1004;
  static const int predictionAlertId = 1005;

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iOSSettings =
        DarwinInitializationSettings();

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iOSSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  // Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // Handle action here - navigate to relevant screen
    if (response.payload != null) {
      // Parse payload and navigate
      final parts = response.payload!.split(':');
      if (parts[0] == 'anomaly') {
        // Navigate to prediction screen
      } else if (parts[0] == 'prediction') {
        // Navigate to prediction details
      }
    }
  }

  // 🚨 Send anomaly alert notification
  static Future<void> sendAnomalyAlert({
    required String title,
    required String body,
    required double voltage,
    required double current,
    required double power,
    required String anomalyType,
  }) async {
    int notificationId = anomalyAlertId;
    
    // Use specific ID based on anomaly type
    if (anomalyType.contains('Overvoltage')) {
      notificationId = overvoltageAlertId;
    } else if (anomalyType.contains('Overcurrent')) {
      notificationId = overcurrentAlertId;
    } else if (anomalyType.contains('Overpower')) {
      notificationId = overpowerAlertId;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'anomaly_channel',
      'Anomaly Alerts',
      channelDescription: 'Critical alerts for power anomalies',
      importance: Importance.max,
      priority: Priority.high,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: true,
    );

    const DarwinNotificationDetails iOSDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      badgeNumber: 1,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      notificationDetails,
      payload: 'anomaly:$anomalyType',
    );

    // Log to server
    await _logAnomalyNotification(
      anomalyType: anomalyType,
      voltage: voltage,
      current: current,
      power: power,
    );
  }

  // ⚠️ Send prediction warning notification
  static Future<void> sendPredictionWarning({
    required String title,
    required String body,
    required String predictedIssue,
    String? recommendation,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'prediction_channel',
      'Prediction Alerts',
      channelDescription: 'Alerts based on energy predictions',
      importance: Importance.high,
      priority: Priority.high,
      enableLights: true,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iOSDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    String displayBody = body;
    if (recommendation != null) {
      displayBody = '$body\n💡 Tip: $recommendation';
    }

    await _notificationsPlugin.show(
      predictionAlertId,
      title,
      displayBody,
      notificationDetails,
      payload: 'prediction:$predictedIssue',
    );
  }

  // 📱 Send summary notification
  static Future<void> sendDailySummary({
    required String dailyEnergy,
    required String peakPower,
    required String averagePower,
    required int anomalyCount,
  }) async {
    String title = '📊 Daily Energy Summary';
    String body = 'Energy: $dailyEnergy | Peak: $peakPower | Avg: $averagePower';
    
    if (anomalyCount > 0) {
      title = '⚠️ Daily Summary with Anomalies';
      body = '$body\n$anomalyCount anomalies detected';
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'summary_channel',
      'Daily Summary',
      channelDescription: 'Daily energy consumption summary',
      importance: Importance.low,
      priority: Priority.low,
      enableVibration: false,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
    );
  }

  // 🔌 Send relay control notification
  static Future<void> sendRelayControlNotification({
    required bool isOn,
    required String reason,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'relay_channel',
      'Relay Control',
      channelDescription: 'Notifications for relay status changes',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      2001,
      isOn ? '🔌 Power Enabled' : '⚫ Power Disabled',
      'Reason: $reason',
      notificationDetails,
    );
  }

  // 📧 Log notification to server
  static Future<void> _logAnomalyNotification({
    required String anomalyType,
    required double voltage,
    required double current,
    required double power,
  }) async {
    try {
      await ApiService.post(
        '/notifications/log-anomaly',
        {
          'anomalyType': anomalyType,
          'voltage': voltage,
          'current': current,
          'power': power,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('Error logging anomaly notification: $e');
    }
  }

  // 🧹 Cancel all notifications
  static Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }

  // 🗑️ Cancel specific notification
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}
