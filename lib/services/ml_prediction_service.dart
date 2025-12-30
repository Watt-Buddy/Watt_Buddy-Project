import 'api_service.dart';

class MLPredictionService {
  // 🧠 Predict next hour power consumption
  static Future<Map<String, dynamic>?> predictNextHour(
    String userId,
  ) async {
    try {
      final data = await ApiService.get(
        '/ml-predict/next-hour/$userId',
      );

      if (data['success'] == true && data['prediction'] != null) {
        final pred = data['prediction'];
        return {
          'predictedPower': pred['predictedPower'] ?? 0.0,
          'confidence': pred['confidence'] ?? 0.0,
          'trend': pred['trend'] ?? 'stable',
          'recommendation': pred['recommendation'] ?? '',
        };
      }
      return null;
    } catch (e) {
      print('❌ Error predicting next hour: $e');
      return null;
    }
  }

  // Predict next day power consumption
  static Future<Map<String, dynamic>?> predictNextDay(
    String userId,
  ) async {
    try {
      final data = await ApiService.get(
        '/ml-predict/next-day/$userId',
      );

      if (data['success'] == true && data['prediction'] != null) {
        final pred = data['prediction'];
        return {
          'predictedDailyEnergy': pred['predictedDailyEnergy'] ?? 0.0,
          'predictedPeakPower': pred['predictedPeakPower'] ?? 0.0,
          'confidence': pred['confidence'] ?? 0.0,
          'anomalyDetected': pred['anomalyDetected'] ?? false,
          'advice': pred['adviceIfAnomalous'] ?? '',
        };
      }
      return null;
    } catch (e) {
      print('❌ Error predicting next day: $e');
      return null;
    }
  }

  // Detect anomalies in power usage
  static Future<List<Map<String, dynamic>>?> detectAnomalies(
    String userId,
  ) async {
    try {
      final data = await ApiService.get(
        '/ml-predict/anomalies/$userId',
      );

      if (data['success'] == true && data['anomalies'] != null) {
        return List<Map<String, dynamic>>.from(data['anomalies']);
      }
      return [];
    } catch (e) {
      print('❌ Error detecting anomalies: $e');
      return [];
    }
  }

  // Get energy saving recommendations
  static Future<Map<String, dynamic>?> getRecommendations(
    String userId,
  ) async {
    try {
      final data = await ApiService.get(
        '/ml-predict/recommendations/$userId',
      );

      if (data['success'] == true && data['recommendations'] != null) {
        return {
          'recommendations': List<String>.from(data['recommendations']),
        };
      }
      return null;
    } catch (e) {
      print('❌ Error getting recommendations: $e');
      return null;
    }
  }

  // Format predictions for UI display
  static String formatTrendIcon(String trend) {
    switch (trend.toLowerCase()) {
      case 'increasing':
        return '📈 Increasing';
      case 'decreasing':
        return '📉 Decreasing';
      case 'stable':
      default:
        return '➡️ Stable';
    }
  }

  // Get confidence color based on score
  static String getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return 'Green'; // High confidence
    if (confidence >= 0.6) return 'Yellow'; // Medium confidence
    return 'Orange'; // Low confidence
  }
}
