import 'package:flutter/material.dart';
import 'power_limit_service.dart';
import 'esp32_storage_service.dart';
import 'realtime_graph_service.dart';
import 'ml_prediction_service.dart';

/// Example: How to integrate all 4 features into a dashboard screen
class EnergyDashboardIntegration {
  final String userId;

  EnergyDashboardIntegration({required this.userId});

  /// 📊 Complete dashboard initialization
  Future<Map<String, dynamic>> initializeDashboard() async {
    print('🚀 Initializing WattBuddy Dashboard with 4 Features...\n');

    // Feature 1️⃣: Get power limit settings
    print('1️⃣ Fetching Power Limit Settings...');
    final powerLimitSettings = 
        await PowerLimitNotificationService.getPowerLimitSettings(userId);
    print('✅ Power Limit: ${powerLimitSettings?['daily_power_limit']} W\n');

    // Feature 2️⃣: Get latest ESP32 readings
    print('2️⃣ Fetching Latest ESP32 Data...');
    final latestReadings = 
        await ESP32StorageService.getLatestReadings(userId, limit: 10);
    print('✅ Retrieved ${latestReadings?.length ?? 0} readings\n');

    // Feature 3️⃣: Get real-time graph data
    print('3️⃣ Fetching Real-Time Graph Data (Last 60 minutes)...');
    final graphData = 
        await RealtimeGraphService.getLiveGraphData(userId, minutes: 60);
    print('✅ Graph points: ${graphData?.length ?? 0}\n');

    // Feature 4️⃣: Get ML predictions
    print('4️⃣ Generating ML Predictions...');
    final nextHourPrediction = 
        await MLPredictionService.predictNextHour(userId);
    final nextDayPrediction = 
        await MLPredictionService.predictNextDay(userId);
    final anomalies = 
        await MLPredictionService.detectAnomalies(userId);
    final recommendations = 
        await MLPredictionService.getRecommendations(userId);

    print('✅ Next Hour Prediction: ${nextHourPrediction?['predictedPower']?.toStringAsFixed(2)} W');
    print('✅ Next Day Prediction: ${nextDayPrediction?['predictedDailyEnergy']?.toStringAsFixed(2)} Wh');
    print('✅ Anomalies Detected: ${anomalies?.length ?? 0}');
    print('✅ Recommendations: ${recommendations?['recommendations']?.length ?? 0}\n');

    return {
      'powerLimitSettings': powerLimitSettings,
      'latestReadings': latestReadings,
      'graphData': graphData,
      'nextHourPrediction': nextHourPrediction,
      'nextDayPrediction': nextDayPrediction,
      'anomalies': anomalies,
      'recommendations': recommendations,
    };
  }

  /// Process ESP32 reading with all features
  Future<void> processEsp32Reading({
    required double power,
    required double voltage,
    required double current,
    required double energy,
    required double pf,
    required double frequency,
    required double temperature,
  }) async {
    print('📡 Processing new ESP32 reading...\n');

    // Feature 2️⃣: Store in database
    print('💾 Storing in PostgreSQL...');
    final stored = await ESP32StorageService.storeReading(
      userId: userId,
      power: power,
      voltage: voltage,
      current: current,
      energy: energy,
      pf: pf,
      frequency: frequency,
      temperature: temperature,
    );
    print('✅ Data stored: $stored\n');

    // Feature 1️⃣: Check power limit
    print('⚡ Checking power limit...');
    final settings = 
        await PowerLimitNotificationService.getPowerLimitSettings(userId);
    final dailyLimit = settings?['daily_power_limit'] ?? 5000;
    
    await PowerLimitNotificationService.checkAndNotifyPowerLimit(
      userId,
      power,
      dailyLimit,
    );
    print('✅ Power limit check complete\n');

    // Feature 3️⃣: Update real-time graph
    print('📊 Updating real-time graph...');
    final graphData = 
        await RealtimeGraphService.getLiveGraphData(userId, minutes: 60);
    final stats = RealtimeGraphService.calculateStats(graphData ?? []);
    print('✅ Current: ${stats['current']?.toStringAsFixed(2)} W');
    print('✅ Average: ${stats['avg']?.toStringAsFixed(2)} W');
    print('✅ Peak: ${stats['max']?.toStringAsFixed(2)} W\n');

    // Feature 4️⃣: Update predictions
    print('🧠 Updating ML predictions...');
    final nextHour = await MLPredictionService.predictNextHour(userId);
    print('✅ Predicted next hour: ${nextHour?['predictedPower']?.toStringAsFixed(2)} W');
    print('✅ Trend: ${MLPredictionService.formatTrendIcon(nextHour?['trend'] ?? 'stable')}\n');
  }

  /// Example dashboard widget
  static Widget buildDashboardWidget({
    required String userId,
    required Map<String, dynamic> dashboardData,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Power Limit Widget
          _buildPowerLimitWidget(dashboardData['powerLimitSettings']),
          const SizedBox(height: 16),

          // Real-Time Stats
          _buildRealtimeStatsWidget(dashboardData['graphData']),
          const SizedBox(height: 16),

          // Predictions
          _buildPredictionsWidget(
            dashboardData['nextHourPrediction'],
            dashboardData['nextDayPrediction'],
          ),
          const SizedBox(height: 16),

          // Recommendations
          _buildRecommendationsWidget(dashboardData['recommendations']),
          const SizedBox(height: 16),

          // Anomalies Alert
          if (dashboardData['anomalies'] != null && 
              dashboardData['anomalies'].isNotEmpty)
            _buildAnomaliesWidget(dashboardData['anomalies']),
        ],
      ),
    );
  }

  static Widget _buildPowerLimitWidget(Map<String, dynamic>? settings) {
    if (settings == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Loading power limit settings...'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔔 Power Limit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Daily Limit: ${settings['daily_power_limit']} W'),
            Text('Alert Threshold: ${(settings['alert_threshold'] * 100).toStringAsFixed(0)}%'),
          ],
        ),
      ),
    );
  }

  static Widget _buildRealtimeStatsWidget(List<Map<String, dynamic>>? data) {
    if (data == null || data.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('📊 No data available'),
        ),
      );
    }

    final stats = RealtimeGraphService.calculateStats(data);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📊 Real-Time Statistics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Current'),
                    Text('${stats['current']?.toStringAsFixed(1)} W', 
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Average'),
                    Text('${stats['avg']?.toStringAsFixed(1)} W',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    const Text('Peak'),
                    Text('${stats['max']?.toStringAsFixed(1)} W',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildPredictionsWidget(
    Map<String, dynamic>? nextHour,
    Map<String, dynamic>? nextDay,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🧠 ML Predictions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (nextHour != null) ...[
              Text('Next Hour: ${nextHour['predictedPower']?.toStringAsFixed(1)} W'),
              Text('Trend: ${MLPredictionService.formatTrendIcon(nextHour['trend'] ?? 'stable')}'),
              Text('Confidence: ${(nextHour['confidence'] * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: 8),
            ],
            if (nextDay != null) ...[
              Text('Next Day: ${nextDay['predictedDailyEnergy']?.toStringAsFixed(1)} Wh'),
              Text('Peak: ${nextDay['predictedPeakPower']?.toStringAsFixed(1)} W'),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _buildRecommendationsWidget(Map<String, dynamic>? recs) {
    final recsList = recs?['recommendations'] as List<dynamic>?;
    if (recsList == null || recsList.isEmpty) {
      return const SizedBox.shrink();
    }

    final recommendations = recsList.cast<String>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💡 Energy-Saving Tips', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...recommendations.map((rec) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('• $rec'),
            )),
          ],
        ),
      ),
    );
  }

  static Widget _buildAnomaliesWidget(List<Map<String, dynamic>>? anomalies) {
    if (anomalies == null || anomalies.isEmpty) return const SizedBox.shrink();

    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('⚠️ Anomalies Detected', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
            const SizedBox(height: 12),
            Text('${anomalies.length} unusual patterns detected in last 7 days'),
          ],
        ),
      ),
    );
  }
}

/// Example usage in main screen
void exampleUsage() {
  final dashboard = EnergyDashboardIntegration(userId: 'user_123');

  // Initialize and display dashboard
  dashboard.initializeDashboard().then((data) {
    print('Dashboard data loaded!');
    // Build UI with data
  });

  // Process new ESP32 reading
  dashboard.processEsp32Reading(
    power: 2500,
    voltage: 230,
    current: 10.87,
    energy: 0.5,
    pf: 0.95,
    frequency: 50,
    temperature: 28,
  );
}
