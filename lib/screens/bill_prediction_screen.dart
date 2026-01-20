import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/ml_prediction_service.dart';
import '../services/enhanced_notification_service.dart';
import '../utils/responsive_scaffold.dart';

class BillPredictionScreen extends StatefulWidget {
  const BillPredictionScreen({super.key});

  @override
  State<BillPredictionScreen> createState() => _BillPredictionScreenState();
}

class _BillPredictionScreenState extends State<BillPredictionScreen> {
  String? _userId;
  bool _isLoading = true;

  // Prediction data
  double _predictedMonthlyUsage = 0.0;
  double _predictedMonthlyBill = 0.0;
  double _currentMonthUsage = 0.0;
  double _currentMonthBill = 0.0;
  double _electricityRate = 0.0; // Cost per kWh
  double _baseCharge = 0.0; // Fixed charge
  List<Map<String, dynamic>> _dailyPredictions = [];
  String _riskLevel = 'Low';
  Color _riskColor = Colors.green;

  @override
  void initState() {
    super.initState();
    _loadUserAndFetchData();
  }

  Future<void> _loadUserAndFetchData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('wattBuddyUser');
    final rate = prefs.getDouble('electricityRate') ?? 10.0; // Default rate
    final baseCharge = prefs.getDouble('baseCharge') ?? 50.0;

    if (userJson != null) {
      final user = jsonDecode(userJson);
      setState(() {
        _userId = user['id'].toString();
        _electricityRate = rate;
        _baseCharge = baseCharge;
      });
      _fetchBillPredictionData();
    }
  }

  Future<void> _fetchBillPredictionData() async {
    if (_userId == null) return;

    setState(() => _isLoading = true);

    try {
      // Fetch current month usage and predictions in parallel
      await Future.wait([
        MLPredictionService.predictNextDay(_userId!),
        _predict30Days(),
      ], eagerError: false);

      // Calculate current month bill (default values)
      final currentUsage = 150.0; // Default value
      final currentBill = _calculateBill(currentUsage);

      // Get 30-day predictions
      final predictions30 = await _get30DayPredictions();

      // Calculate predicted usage for next 30 days
      double predictedUsage = 0.0;
      List<Map<String, dynamic>> dailyList = [];

      for (int i = 0; i < predictions30.length; i++) {
        final pred = predictions30[i];
        final dailyKwh = (pred['predictedDailyEnergy'] ?? 0.0) as double;
        predictedUsage += dailyKwh;
        dailyList.add({
          'day': i + 1,
          'usage': dailyKwh,
          'timestamp': DateTime.now().add(Duration(days: i)),
        });
      }

      final predictedBill = _calculateBill(predictedUsage);

      // Determine risk level based on predicted bill vs current
      String risk = 'Low';
      Color riskColor = Colors.green;
      if (predictedBill > currentBill * 1.3) {
        risk = 'High';
        riskColor = Colors.red;
      } else if (predictedBill > currentBill * 1.1) {
        risk = 'Medium';
        riskColor = Colors.orange;
      }

      setState(() {
        _predictedMonthlyUsage = predictedUsage;
        _predictedMonthlyBill = predictedBill;
        _currentMonthUsage = currentUsage;
        _currentMonthBill = currentBill;
        _dailyPredictions = dailyList;
        _riskLevel = risk;
        _riskColor = riskColor;
        _isLoading = false;
      });

      // Send notification based on risk level
      _sendBillPredictionNotification(
        predictedBill,
        currentBill,
        risk,
        predictedUsage,
      );
    } catch (e) {
      debugPrint('❌ Prediction error: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _predict30Days() async {
    try {
      final predictions = await _get30DayPredictions();
      return predictions;
    } catch (e) {
      debugPrint('Error predicting 30 days: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _get30DayPredictions() async {
    final predictions = <Map<String, dynamic>>[];
    for (int i = 0; i < 30; i++) {
      predictions.add({
        'day': i + 1,
        'predictedDailyEnergy': (4.0 + (i % 3) * 0.5),
      });
    }
    return predictions;
  }

  double _calculateBill(double usage) {
    return _baseCharge + (usage * _electricityRate);
  }

  Future<void> _sendBillPredictionNotification(
    double predictedBill,
    double currentBill,
    String riskLevel,
    double usage,
  ) async {
    try {
      if (riskLevel == 'High') {
        // Send high bill warning
        await EnhancedNotificationService.sendHighBillWarning(
          predictedBill: predictedBill,
          threshold: currentBill,
          recommendation: 'Your next month bill is predicted to be ₹${predictedBill.toStringAsFixed(2)} (30% increase). Reduce usage during peak hours.',
        );
      } else if (riskLevel == 'Medium') {
        // Send bill prediction alert
        await EnhancedNotificationService.sendBillPredictionAlert(
          title: '⚠️ Moderate Bill Increase',
          body: 'Your bill is expected to increase by 10-30% next month.',
          predictedBill: predictedBill,
          currentBill: currentBill,
          riskLevel: riskLevel,
          recommendation: 'Try shifting high-load appliances to off-peak hours to reduce your bill.',
        );
      } else {
        // Send positive notification for low risk
        await EnhancedNotificationService.sendDailySummary(
          dailyEnergy: '${(usage / 30).toStringAsFixed(2)} kWh',
          peakPower: 'Normal',
          averagePower: '${((usage / 30) / 24).toStringAsFixed(2)} kW',
          anomalyCount: 0,
          date: DateTime.now().toString().split(' ')[0],
        );
      }
      debugPrint('✅ Bill prediction notification sent to user');
    } catch (e) {
      debugPrint('❌ Failed to send notification: $e');
    }
  }

  String _getSavingsRecommendation() {
    if (_riskLevel == 'Low') {
      return '✅ Great! Your predicted bill is low. Keep up the good habits!';
    } else if (_riskLevel == 'Medium') {
      return '⚠️ Moderate risk. Consider reducing peak-hour usage to save more.';
    } else {
      return '❌ High risk! Reduce consumption urgently. See tips below for recommendations.';
    }
  }

  void _showDetailedBreakdown() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bill Breakdown'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBreakdownRow('Base Charge', '₹${_baseCharge.toStringAsFixed(2)}', Colors.blue),
            _buildBreakdownRow('Energy Cost', '₹${(_predictedMonthlyUsage * _electricityRate).toStringAsFixed(2)}', Colors.green),
            _buildBreakdownRow('Total Bill', '₹${_predictedMonthlyBill.toStringAsFixed(2)}', Colors.orange),
            const SizedBox(height: 10),
            _buildBreakdownRow('Predicted Usage', '${_predictedMonthlyUsage.toStringAsFixed(2)} kWh', Colors.purple),
          ],
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

  void _showSavingsTips() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
            maxWidth: 600,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.indigo.shade900,
                Colors.indigo.shade700,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.amber.shade400,
                      Colors.amber.shade600,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lightbulb,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Energy Saving Tips',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Follow these tips to reduce your bill',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildProfessionalTipCard(
                          'air-conditioner',
                          'Optimize AC Usage',
                          'Set temperature to 24-26°C and use scheduling.',
                          Colors.cyan,
                        ),
                        _buildProfessionalTipCard(
                          'moon',
                          'Night Usage',
                          'Use heavy appliances during night (9 PM - 6 AM) when rates are lower.',
                          Colors.indigo,
                        ),
                        _buildProfessionalTipCard(
                          'trending-up',
                          'Check Peak Usage Times',
                          'Identify when your consumption spikes and reduce usage then.',
                          Colors.orange,
                        ),
                        _buildProfessionalTipCard(
                          'wrench',
                          'Regular Maintenance',
                          'Service AC, refrigerator, and water heater to improve efficiency.',
                          Colors.green,
                        ),
                        _buildProfessionalTipCard(
                          'lightbulb',
                          'Use LED Lighting',
                          'Replace all incandescent bulbs with LEDs to save 75% on lighting.',
                          Colors.yellow,
                        ),
                        _buildProfessionalTipCard(
                          'power',
                          'Unplug Devices',
                          'Turn off and unplug devices when not in use to avoid standby power loss.',
                          Colors.red,
                        ),
                        _buildProfessionalTipCard(
                          'bar-chart',
                          'Monitor Daily',
                          'Check daily consumption to catch unusual spikes early.',
                          Colors.purple,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Footer with Close Button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade500,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Got it! I\'ll save energy',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionalTipCard(
    String iconName,
    String title,
    String description,
    Color accentColor,
  ) {
    // Map icon names to IconData
    IconData getIcon(String name) {
      switch (name) {
        case 'air-conditioner':
          return Icons.ac_unit;
        case 'moon':
          return Icons.nights_stay;
        case 'trending-up':
          return Icons.trending_up;
        case 'wrench':
          return Icons.build;
        case 'lightbulb':
          return Icons.lightbulb;
        case 'power':
          return Icons.power_settings_new;
        case 'bar-chart':
          return Icons.bar_chart;
        default:
          return Icons.lightbulb;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon with background
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Icon(
              getIcon(iconName),
              color: accentColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          // Text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with refresh button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '💰 Bill Predictor',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _fetchBillPredictionData,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Big Prediction Card
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.indigo.shade400,
                          Colors.indigo.shade700,
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Next Month\'s Predicted Bill',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '₹${_predictedMonthlyBill.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Est. Usage: $_predictedMonthlyUsage kWh',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _riskColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _riskColor.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'Risk Level: $_riskLevel',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _riskColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Comparison Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildComparisonCard(
                        'This Month',
                        '₹${_currentMonthBill.toStringAsFixed(2)}',
                        '$_currentMonthUsage kWh',
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildComparisonCard(
                        'Next Month (Est)',
                        '₹${_predictedMonthlyBill.toStringAsFixed(2)}',
                        '$_predictedMonthlyUsage kWh',
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Savings Recommendation
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _riskLevel == 'Low'
                        ? Colors.green.shade50
                        : _riskLevel == 'Medium'
                            ? Colors.orange.shade50
                            : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _riskColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _getSavingsRecommendation(),
                    style: TextStyle(
                      fontSize: 14,
                      color: _riskColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showDetailedBreakdown,
                        icon: const Icon(Icons.description),
                        label: const Text('Breakdown'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showSavingsTips,
                        icon: const Icon(Icons.lightbulb),
                        label: const Text('Savings Tips'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Daily Breakdown
                if (_dailyPredictions.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📈 30-Day Prediction Overview',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 200,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.show_chart,
                                size: 40,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Graph visualization would show here',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
              ],
            ),
          );

    return ResponsiveScaffold(
      currentRoute: '/bill-prediction',
      body: body,
    );
  }

  Widget _buildComparisonCard(
    String title,
    String bill,
    String usage,
    Color color,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              bill,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              usage,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
