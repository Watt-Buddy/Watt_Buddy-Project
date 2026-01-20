import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

/// Enhanced Notification Service with Anomaly Detection & Bill Prediction Alerts
class EnhancedNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Notification channel IDs
  static const String anomalyChannel = 'anomaly_alerts';
  static const String billPredictionChannel = 'bill_prediction_alerts';
  static const String summaryChannel = 'daily_summary';
  static const String relayChannel = 'relay_control';
  static const String criticalChannel = 'critical_alerts';

  // Notification IDs
  static const int anomalyAlertId = 1001;
  static const int billPredictionId = 1002;
  static const int summaryId = 1003;
  static const int relayId = 2001;
  static const int criticalAlertId = 3001;

  /// Initialize notification service with all channels
  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iOSSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iOSSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationTapped,
    );

    // Create notification channels for Android
    await _createNotificationChannels();

    debugPrint('✅ Enhanced Notification Service Initialized');
  }

  /// Create Android notification channels
  static Future<void> _createNotificationChannels() async {
    // Notification channels are auto-created by flutter_local_notifications
    // This method is kept for future customization if needed
    debugPrint('✅ Notification channels ready');
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Notification tapped: ${response.payload}');
    if (response.payload != null) {
      _handleNotificationPayload(response.payload!);
    }
  }

  /// Handle background notification
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTapped(NotificationResponse response) {
    debugPrint('🔔 Background notification tapped: ${response.payload}');
  }

  /// Parse and handle notification payload
  static void _handleNotificationPayload(String payload) {
    final parts = payload.split(':');
    final type = parts[0];

    switch (type) {
      case 'anomaly':
        // Handle anomaly notification
        debugPrint('⚠️ Anomaly action triggered');
        break;
      case 'bill_prediction':
        // Handle bill prediction notification
        debugPrint('💰 Bill prediction action triggered');
        break;
      case 'summary':
        // Handle summary notification
        debugPrint('📊 Summary action triggered');
        break;
      default:
        debugPrint('Unknown notification type: $type');
    }
  }

  // ========== ANOMALY DETECTION NOTIFICATIONS ==========

  /// Send anomaly detection alert
  static Future<void> sendAnomalyAlert({
    required String title,
    required String body,
    required String anomalyType,
    double? voltage,
    double? current,
    double? power,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      anomalyChannel,
      'Anomaly Alerts',
      channelDescription: 'Critical alerts for power anomalies',
      importance: Importance.max,
      priority: Priority.max,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: true,
      styleInformation: BigTextStyleInformation(''),
    );

    const DarwinNotificationDetails iOSDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      badgeNumber: 1,
      sound: 'notification.caf',
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    String displayBody = body;
    if (voltage != null && current != null && power != null) {
      displayBody =
          '$body\nV: ${voltage.toStringAsFixed(1)}V | I: ${current.toStringAsFixed(2)}A | P: ${power.toStringAsFixed(0)}W';
    }

    await _notificationsPlugin.show(
      anomalyAlertId,
      title,
      displayBody,
      notificationDetails,
      payload: 'anomaly:$anomalyType',
    );

    // Log to server
    await _logAnomalyToServer(
      anomalyType: anomalyType,
      voltage: voltage ?? 0,
      current: current ?? 0,
      power: power ?? 0,
    );
  }

  // ========== BILL PREDICTION NOTIFICATIONS ==========

  /// Send bill prediction alert
  static Future<void> sendBillPredictionAlert({
    required String title,
    required String body,
    required double predictedBill,
    required double currentBill,
    required String riskLevel,
    String? recommendation,
  }) async {
    String displayBody =
        'Next month: ₹${predictedBill.toStringAsFixed(2)} | Current: ₹${currentBill.toStringAsFixed(2)}\n$body';

    if (recommendation != null) {
      displayBody = '$displayBody\n💡 $recommendation';
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      billPredictionChannel,
      'Bill Predictions',
      channelDescription: 'Alerts about predicted electricity bills',
      importance: Importance.high,
      priority: Priority.high,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      styleInformation: BigTextStyleInformation(''),
    );

    const DarwinNotificationDetails iOSDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _notificationsPlugin.show(
      billPredictionId,
      title,
      displayBody,
      notificationDetails,
      payload:
          'bill_prediction:${predictedBill.toStringAsFixed(2)}:$riskLevel',
    );

    // Log to server
    await _logBillPredictionToServer(
      predictedBill: predictedBill,
      currentBill: currentBill,
      riskLevel: riskLevel,
    );
  }

  /// Send high bill warning alert
  static Future<void> sendHighBillWarning({
    required double predictedBill,
    required double threshold,
    String? recommendation,
  }) async {
    final percentageIncrease =
        ((predictedBill - threshold) / threshold * 100).toStringAsFixed(1);

    String title = '⚠️ High Bill Alert!';
    String body =
        'Your next month bill is predicted to be ₹${predictedBill.toStringAsFixed(2)} (+$percentageIncrease%)';

    recommendation ??= 'Consider shifting load to off-peak hours to reduce consumption.';

    await sendBillPredictionAlert(
      title: title,
      body: body,
      predictedBill: predictedBill,
      currentBill: threshold,
      riskLevel: 'High',
      recommendation: recommendation,
    );
  }

  // ========== DAILY SUMMARY NOTIFICATIONS ==========

  /// Send daily energy summary
  static Future<void> sendDailySummary({
    required String dailyEnergy,
    required String peakPower,
    required String averagePower,
    required int anomalyCount,
    required String date,
  }) async {
    String title = '📊 Daily Energy Summary';
    String body = '$date\nEnergy: $dailyEnergy | Peak: $peakPower | Avg: $averagePower';

    if (anomalyCount > 0) {
      title = '⚠️ Summary: $anomalyCount anomalies detected';
      body = '$body\n⚠️ $anomalyCount anomalies found today';
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      summaryChannel,
      'Daily Summary',
      channelDescription: 'Daily energy consumption summaries',
      importance: Importance.low,
      priority: Priority.low,
      enableVibration: false,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      summaryId,
      title,
      body,
      notificationDetails,
      payload: 'summary:$date:$anomalyCount',
    );
  }

  // ========== RELAY CONTROL NOTIFICATIONS ==========

  /// Send relay status notification
  static Future<void> sendRelayStatusNotification({
    required bool isOn,
    required String reason,
    String? duration,
  }) async {
    String title = isOn ? '🔌 Power Enabled' : '⚫ Power Disabled';
    String body = 'Reason: $reason';

    if (duration != null) {
      body = '$body\nDuration: $duration';
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      relayChannel,
      'Relay Control',
      channelDescription: 'Relay switch status notifications',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      relayId,
      title,
      body,
      notificationDetails,
      payload: 'relay:${isOn ? 'on' : 'off'}:$reason',
    );
  }

  // ========== CRITICAL ALERTS ==========

  /// Send critical alert
  static Future<void> sendCriticalAlert({
    required String title,
    required String body,
    required String alertType,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      criticalChannel,
      'Critical Alerts',
      channelDescription: 'Critical system alerts',
      importance: Importance.max,
      priority: Priority.max,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      fullScreenIntent: true,
      styleInformation: BigTextStyleInformation(''),
    );

    const DarwinNotificationDetails iOSDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      badgeNumber: 1,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await _notificationsPlugin.show(
      criticalAlertId,
      title,
      body,
      notificationDetails,
      payload: 'critical:$alertType',
    );
  }

  // ========== SERVER LOGGING ==========

  /// Log anomaly detection to server
  static Future<void> _logAnomalyToServer({
    required String anomalyType,
    required double voltage,
    required double current,
    required double power,
  }) async {
    try {
      await ApiService.post(
        '/api/notifications/log-anomaly',
        {
          'anomalyType': anomalyType,
          'voltage': voltage,
          'current': current,
          'power': power,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('❌ Error logging anomaly to server: $e');
    }
  }

  /// Log bill prediction alert to server
  static Future<void> _logBillPredictionToServer({
    required double predictedBill,
    required double currentBill,
    required String riskLevel,
  }) async {
    try {
      await ApiService.post(
        '/api/notifications/log-bill-prediction',
        {
          'predictedBill': predictedBill,
          'currentBill': currentBill,
          'riskLevel': riskLevel,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      debugPrint('❌ Error logging bill prediction to server: $e');
    }
  }

  // ========== NOTIFICATION MANAGEMENT ==========

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
    debugPrint('🧹 All notifications cleared');
  }

  /// Cancel specific notification by ID
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    debugPrint('❌ Notification $id cancelled');
  }

  /// Request iOS notification permissions
  static Future<bool> requestIOSPermissions() async {
    final iOSPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

    if (iOSPlugin != null) {
      final granted = await iOSPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  /// Request Android notification permissions (Android 13+)
  static Future<bool> requestAndroidPermissions() async {
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }
    return false;
  }

  /// Get notification settings summary
  static String getNotificationInfo() {
    return '''
    📱 Enhanced Notification Service
    ✅ Anomaly Detection Alerts
    ✅ Bill Prediction Alerts
    ✅ Daily Summary Notifications
    ✅ Relay Control Status
    ✅ Critical Alerts
    ''';
  }
}
