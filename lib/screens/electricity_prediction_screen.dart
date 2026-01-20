import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/ml_prediction_service.dart';

class ElectricityPredictionScreen extends StatefulWidget {
  const ElectricityPredictionScreen({Key? key}) : super(key: key);

  @override
  State<ElectricityPredictionScreen> createState() =>
      _ElectricityPredictionScreenState();
}

class _ElectricityPredictionScreenState
    extends State<ElectricityPredictionScreen> {
  String? _userId;
  bool _isLoading = true;

  // Prediction data
  Map<String, dynamic>? _nextHourPrediction;
  Map<String, dynamic>? _nextDayPrediction;
  List<Map<String, dynamic>>? _anomalies;
  Map<String, dynamic>? _recommendations;

  // Anomaly detection
  bool _hasAnomalies = false;
  String _anomalyStatus = 'Normal';
  Color _anomalyColor = Colors.green;

  @override
  void initState() {
    super.initState();
    _loadUserAndFetchData();
  }

  Future<void> _loadUserAndFetchData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('wattBuddyUser');

    if (userJson != null) {
      final user = jsonDecode(userJson);
      setState(() => _userId = user['id'].toString());
      _fetchPredictionData();
    }
  }

  Future<void> _fetchPredictionData() async {
    if (_userId == null) return;

    setState(() => _isLoading = true);

    try {
      // Fetch all data in parallel
      final results = await Future.wait([
        MLPredictionService.predictNextHour(_userId!),
        MLPredictionService.predictNextDay(_userId!),
        MLPredictionService.detectAnomalies(_userId!),
        MLPredictionService.getRecommendations(_userId!),
      ]);

      final nextHour = results[0] as Map<String, dynamic>?;
      final nextDay = results[1] as Map<String, dynamic>?;
      final anomalies = results[2] as List<Map<String, dynamic>>?;
      final recommendations = results[3] as Map<String, dynamic>?;

      setState(() {
        _nextHourPrediction = nextHour;
        _nextDayPrediction = nextDay;
        _anomalies = anomalies;
        _recommendations = recommendations;

        // Check if anomalies exist
        _hasAnomalies = (anomalies != null && anomalies.isNotEmpty) ||
            (nextDay?['anomalyDetected'] == true);

        if (_hasAnomalies) {
          _anomalyStatus = '⚠️ Anomalies Detected!';
          _anomalyColor = Colors.red;
        } else {
          _anomalyStatus = '✅ All Normal';
          _anomalyColor = Colors.green;
        }

        _isLoading = false;
      });

      // Show notification if anomaly detected
      if (_hasAnomalies) {
        _showAnomalyNotification();
      }
    } catch (e) {
      debugPrint('Error fetching prediction data: $e');
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  void _showAnomalyNotification() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 10),
            Text('Anomaly Alert'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unusual power consumption pattern detected!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            if (_nextDayPrediction?['anomalyDetected'] == true)
              Text(
                'Tomorrow\'s prediction shows: ${_nextDayPrediction?['advice'] ?? 'Check your devices'}',
                style: const TextStyle(fontSize: 13),
              ),
            const SizedBox(height: 15),
            if (_anomalies != null && _anomalies!.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _anomalies!
                      .take(3)
                      .map(
                        (anomaly) => Text(
                          '• ${anomaly['description'] ?? 'Anomaly detected'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade800,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showRecommendations();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('See Recommendations'),
          ),
        ],
      ),
    );
  }

  void _showRecommendations() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lightbulb, color: Colors.amber),
            SizedBox(width: 10),
            Text('Energy Saving Tips'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_recommendations != null &&
                  _recommendations!['recommendations'] != null)
                ...((_recommendations!['recommendations'] as List)
                    .map((rec) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  rec.toString(),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList())
              else
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    'No specific recommendations at this time.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔮 Electricity Prediction'),
        backgroundColor: Colors.deepPurple.shade700,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPredictionData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Anomaly Status Banner
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _anomalyColor.withValues(alpha: 0.3),
                            _anomalyColor.withValues(alpha: 0.1),
                          ],
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _hasAnomalies ? Icons.warning : Icons.check_circle,
                            color: _anomalyColor,
                            size: 50,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _anomalyStatus,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: _anomalyColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _hasAnomalies
                                ? 'Take action to prevent damage'
                                : 'Your power consumption is within normal range',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Next Hour Prediction
                  if (_nextHourPrediction != null)
                    _buildPredictionCard(
                      title: '📊 Next Hour Prediction',
                      icon: Icons.schedule,
                      color: Colors.blue,
                      children: [
                        _buildPredictionRow(
                          'Predicted Power',
                          '${(_nextHourPrediction!['predictedPower'] ?? 0).toStringAsFixed(0)} W',
                          Colors.blue,
                        ),
                        _buildPredictionRow(
                          'Confidence',
                          '${((_nextHourPrediction!['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
                          Colors.blue,
                        ),
                        _buildPredictionRow(
                          'Trend',
                          _nextHourPrediction!['trend'] ?? 'Stable',
                          Colors.blue,
                        ),
                        if (_nextHourPrediction!['recommendation'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '💡 ${_nextHourPrediction!['recommendation']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // Next Day Prediction
                  if (_nextDayPrediction != null)
                    _buildPredictionCard(
                      title: '📅 Tomorrow\'s Prediction',
                      icon: Icons.calendar_today,
                      color: Colors.orange,
                      children: [
                        _buildPredictionRow(
                          'Predicted Daily Energy',
                          '${(_nextDayPrediction!['predictedDailyEnergy'] ?? 0).toStringAsFixed(2)} kWh',
                          Colors.orange,
                        ),
                        _buildPredictionRow(
                          'Peak Power',
                          '${(_nextDayPrediction!['predictedPeakPower'] ?? 0).toStringAsFixed(0)} W',
                          Colors.orange,
                        ),
                        _buildPredictionRow(
                          'Confidence',
                          '${((_nextDayPrediction!['confidence'] ?? 0) * 100).toStringAsFixed(1)}%',
                          Colors.orange,
                        ),
                        if (_nextDayPrediction!['anomalyDetected'] == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '⚠️ ${_nextDayPrediction!['advice'] ?? 'Anomaly may occur'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // Detected Anomalies
                  if (_anomalies != null && _anomalies!.isNotEmpty)
                    _buildAnomaliesCard(),
                  const SizedBox(height: 20),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showRecommendations,
                          icon: const Icon(Icons.lightbulb),
                          label: const Text('Tips'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _fetchPredictionData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPredictionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPredictionRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomaliesCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error, color: Colors.red, size: 28),
                const SizedBox(width: 10),
                const Text(
                  'Detected Anomalies',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            ..._anomalies!
                .map(
                  (anomaly) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                anomaly['type'] ?? 'Anomaly',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                              Text(
                                anomaly['description'] ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ],
        ),
      ),
    );
  }
}
