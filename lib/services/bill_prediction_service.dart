import 'api_service.dart';
import 'enhanced_notification_service.dart';

class BillPredictionService {
  /// Get predicted next month bill
  static Future<Map<String, dynamic>?> getPredictedBill(String userId) async {
    try {
      final data = await ApiService.get(
        '/api/predictions/bill/$userId',
      );

      if (data['success'] == true && data['prediction'] != null) {
        final pred = data['prediction'];
        return {
          'predictedBill': pred['predictedBill'] ?? 0.0,
          'predictedUsage': pred['predictedUsage'] ?? 0.0,
          'currentBill': pred['currentBill'] ?? 0.0,
          'currentUsage': pred['currentUsage'] ?? 0.0,
          'riskLevel': pred['riskLevel'] ?? 'Low',
          'percentageChange': pred['percentageChange'] ?? 0.0,
        };
      }
      return null;
    } catch (e) {
      print('❌ Error predicting bill: $e');
      return null;
    }
  }

  /// Get 30-day consumption predictions
  static Future<List<Map<String, dynamic>>?> get30DayPredictions(
    String userId,
  ) async {
    try {
      final data = await ApiService.get(
        '/api/predictions/30days/$userId',
      );

      if (data['success'] == true && data['predictions'] != null) {
        return List<Map<String, dynamic>>.from(data['predictions']);
      }
      return [];
    } catch (e) {
      print('❌ Error getting 30-day predictions: $e');
      return [];
    }
  }

  /// Check if bill will exceed threshold
  static Future<bool> checkBillThreshold({
    required String userId,
    required double threshold,
  }) async {
    try {
      final billData = await getPredictedBill(userId);
      if (billData != null) {
        final predictedBill = billData['predictedBill'] as double;
        
        if (predictedBill > threshold) {
          // Send alert notification
          await EnhancedNotificationService.sendHighBillWarning(
            predictedBill: predictedBill,
            threshold: threshold,
            recommendation: 'Reduce consumption in peak hours to bring bill down.',
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      print('❌ Error checking bill threshold: $e');
      return false;
    }
  }

  /// Get bill breakdown by appliance
  static Future<Map<String, dynamic>?> getBillBreakdown(String userId) async {
    try {
      final data = await ApiService.get(
        '/api/predictions/breakdown/$userId',
      );

      if (data['success'] == true && data['breakdown'] != null) {
        return {
          'appliances': data['breakdown']['appliances'] ?? [],
          'topConsumer': data['breakdown']['topConsumer'] ?? '',
          'topConsumerUsage': data['breakdown']['topConsumerUsage'] ?? 0.0,
        };
      }
      return null;
    } catch (e) {
      print('❌ Error getting bill breakdown: $e');
      return null;
    }
  }

  /// Get energy saving recommendations based on prediction
  static Future<List<String>?> getSavingsRecommendations(String userId) async {
    try {
      final data = await ApiService.get(
        '/api/predictions/recommendations/$userId',
      );

      if (data['success'] == true && data['recommendations'] != null) {
        return List<String>.from(data['recommendations']);
      }
      return [];
    } catch (e) {
      print('❌ Error getting savings recommendations: $e');
      return [];
    }
  }

  /// Send bill prediction alert
  static Future<void> sendBillAlert({
    required String userId,
    required double predictedBill,
    required double currentBill,
  }) async {
    try {
      final percentageChange =
          ((predictedBill - currentBill) / currentBill * 100);
      String riskLevel = 'Low';
      String title = '💰 Bill Prediction';

      if (percentageChange > 30) {
        riskLevel = 'High';
        title = '⚠️ High Bill Alert!';
      } else if (percentageChange > 10) {
        riskLevel = 'Medium';
        title = '📊 Bill Prediction Alert';
      }

      await EnhancedNotificationService.sendBillPredictionAlert(
        title: title,
        body: 'If you continue consuming at current rate, next month\'s bill will be ₹${predictedBill.toStringAsFixed(2)}',
        predictedBill: predictedBill,
        currentBill: currentBill,
        riskLevel: riskLevel,
        recommendation: riskLevel != 'Low'
            ? 'Consider reducing consumption during peak hours.'
            : null,
      );
    } catch (e) {
      print('❌ Error sending bill alert: $e');
    }
  }

  /// Monitor and send anomaly notifications
  static Future<void> monitorAnomaliesAndAlert({
    required String userId,
    required String anomalyType,
    required double voltage,
    required double current,
    required double power,
  }) async {
    try {
      await EnhancedNotificationService.sendAnomalyAlert(
        title: '⚠️ Anomaly Detected!',
        body: 'Unusual power consumption pattern detected.',
        anomalyType: anomalyType,
        voltage: voltage,
        current: current,
        power: power,
      );
    } catch (e) {
      print('❌ Error sending anomaly alert: $e');
    }
  }

  /// Generate daily summary and send notification
  static Future<void> sendDailySummaryNotification({
    required String userId,
    required double dailyEnergy,
    required double peakPower,
    required double averagePower,
    required int anomalyCount,
  }) async {
    try {
      final date = DateTime.now().toString().split(' ')[0];
      
      await EnhancedNotificationService.sendDailySummary(
        dailyEnergy: '${dailyEnergy.toStringAsFixed(2)} kWh',
        peakPower: '${peakPower.toStringAsFixed(0)} W',
        averagePower: '${averagePower.toStringAsFixed(0)} W',
        anomalyCount: anomalyCount,
        date: date,
      );
    } catch (e) {
      print('❌ Error sending daily summary: $e');
    }
  }
}
