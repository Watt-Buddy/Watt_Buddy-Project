import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../utils/responsive_scaffold.dart';

class BillPredictionScreen extends StatefulWidget {
  const BillPredictionScreen({super.key});

  @override
  State<BillPredictionScreen> createState() => _BillPredictionScreenState();
}

class _BillPredictionScreenState extends State<BillPredictionScreen> {
  String? _userId;
  bool _isLoading = true;

  // Monthly Analytics Data
  double _currentMonthUsage = 0.0;
  double _lastMonthUsage = 0.0;
  double _predictedMonthlyUsage = 0.0;
  double _predictedMonthlyBill = 0.0;
  double _electricityRate = 10.0; 
  double _baseCharge = 50.0;
  
  String _riskLevel = 'Normal';
  Color _riskColor = Colors.green;

  // History for Bar Chart
  List<BarChartGroupData> _barGroups = [];

  @override
  void initState() {
    super.initState();
    _loadUserAndFetchData();
    Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) _fetchBillPredictionData();
    });
  }

  Future<void> _loadUserAndFetchData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('wattBuddyUser');
    if (userJson != null) {
      final user = jsonDecode(userJson);
      setState(() => _userId = user['id'].toString());
      _fetchBillPredictionData();
    }
  }

  Future<void> _fetchBillPredictionData() async {
    if (_userId == null) return;
    setState(() => _isLoading = true);

    try {
      // 1. Fetch Billing Data from SQL View (More accurate server-side calculation)
      final billResponse = await http.get(
        Uri.parse('http://192.168.6.214:4000/api/billing/current/$_userId'),
      );

      if (billResponse.statusCode == 200) {
        final billData = jsonDecode(billResponse.body);
        
        if (billData['success'] && billData['billing'] != null) {
          setState(() {
            // Use double.tryParse to safely convert String/int/double values
            _currentMonthUsage = double.tryParse(
              billData['billing']['total_units_kwh'].toString()
            ) ?? 0.0;
            _predictedMonthlyBill = double.tryParse(
              billData['billing']['slab_bill_rs'].toString()
            ) ?? 0.0;
            _predictedMonthlyUsage = _currentMonthUsage;
            _riskLevel = 'Normal';
            _riskColor = Colors.green;
          });
          debugPrint('✅ Billing data loaded: Usage=${_currentMonthUsage}kWh, Bill=₹${_predictedMonthlyBill}');
        }
      } else {
        // Fallback to manual calculation if billing view fails
        debugPrint('⚠️ Billing endpoint returned ${billResponse.statusCode}');
        await _fetchSummaryDataFallback();
      }

      // 2. Fetch Daily History for the Bar Chart
      await _fetchDailyHistory();

      // 3. Check usage summary for anomaly demo (strong spike detection)
      try {
        final summaryResp = await http.get(
          Uri.parse('http://192.168.6.214:4000/api/usage/summary/$_userId'),
        );

        if (summaryResp.statusCode == 200) {
          final summary = jsonDecode(summaryResp.body);
          if (summary['isAbnormal'] == true) {
            final socketName = summary['anomalySocket'] ?? 'Unknown Socket';
            // Show dialog on next frame to avoid calling during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showAnomalyAlert(socketName);
            });
          }
        }
      } catch (e) {
        debugPrint('⚠️ Anomaly check failed: $e');
      }
    } catch (e) {
      debugPrint('❌ Sync Error: $e');
      // Fallback if billing fetch fails
      try {
        await _fetchSummaryDataFallback();
      } catch (e2) {
        debugPrint('❌ Fallback also failed: $e2');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Fallback method if billing view is not available
  Future<void> _fetchSummaryDataFallback() async {
    if (_userId == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('http://192.168.6.214:4000/api/usage/summary/$_userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        setState(() {
          // Use double.tryParse for safe numeric conversions
          _currentMonthUsage = double.tryParse(
            data['currentMonthKwh'].toString()
          ) ?? 0.0;
          _lastMonthUsage = double.tryParse(
            data['lastMonthKwh'].toString()
          ) ?? 0.0;

          int daysPassed = (data['daysElapsed'] as int?) ?? 1;
          double dailyRate = _currentMonthUsage / (daysPassed > 0 ? daysPassed : 1);
          _predictedMonthlyUsage = dailyRate * 30;
          _predictedMonthlyBill = _baseCharge + (_predictedMonthlyUsage * _electricityRate);

          // Check for abnormal usage flag
          if (data['isAbnormal'] == true) {
            final socketName = data['anomalySocket'] ?? 'Unknown Socket';
            _riskLevel = '⚠️ CRITICAL: ABNORMAL LOAD';
            _riskColor = Colors.red;
            
            // Show high-visibility alert dialog
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showAnomalyAlert(socketName);
            });
            
            final currentPower = double.tryParse(
              data['currentPower'].toString()
            ) ?? 0.0;
            final avgPower = double.tryParse(
              data['historicalAvgPower'].toString()
            ) ?? 0.0;
            
            debugPrint('🚨 ABNORMAL USAGE: Current ${currentPower}W vs Avg ${avgPower}W | Source: $socketName');
          } else {
            double historicalAvg = double.tryParse(
              data['historicalAvgPower'].toString()
            ) ?? 0.0;
            if (historicalAvg > 0 && (dailyRate / 24) > (historicalAvg / 1000) * 1.5) {
              _riskLevel = '⚠️ High Usage Detected';
              _riskColor = Colors.orange;
            } else {
              _riskLevel = 'Normal';
              _riskColor = Colors.green;
            }
          }
          
          debugPrint('✅ Summary data loaded: Usage=${_currentMonthUsage}kWh, Risk=$_riskLevel');
        });
      }
    } catch (e) {
      debugPrint('❌ Fallback Summary Error: $e');
    }
  }

  // Interactive alert dialog for abnormal usage with relay control
  void _showAnomalyAlert(String socketName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A3A),
        title: Text(
          "⚠️ ABNORMAL USAGE: $socketName",
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Power usage is 1.5x higher than normal!",
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Text(
                "Would you like to cut power to $socketName?",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange, width: 1),
                ),
                child: const Text(
                  "💡 Faculty Demo: This demonstrates real-time anomaly detection and device control via your Flutter app.",
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              debugPrint('👤 User neglected the anomaly alert');
            },
            child: const Text(
              "NEGLECT",
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(context);
              _turnOffSocket(socketName);
            },
            child: const Text(
              "TURN OFF SWITCH",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // Turn off the specific socket/relay that's causing the anomaly
  Future<void> _turnOffSocket(String socketName) async {
    try {
      late String endpoint;
      
      if (socketName == "Socket 1") {
        endpoint = '/api/relay/relay1/off';
      } else if (socketName == "Socket 2") {
        endpoint = '/api/relay/relay2/off';
      } else if (socketName == "Both Sockets") {
        // Turn off both relays
        await http.post(Uri.parse('http://192.168.6.214:4000/api/relay/relay1/off'));
        await http.post(Uri.parse('http://192.168.6.214:4000/api/relay/relay2/off'));
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Both sockets turned OFF to prevent damage'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        debugPrint('✅ Emergency cutoff: Both relays disabled');
        return;
      } else {
        return; // Unknown socket
      }

      final response = await http.post(
        Uri.parse('http://192.168.6.214:4000$endpoint'),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $socketName turned OFF successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        debugPrint('✅ $socketName has been safely disabled');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to turn off: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      debugPrint('❌ Relay control error: $e');
    }
  }

  Future<void> _fetchDailyHistory() async {
    if (_userId == null) return;
    try {
      final response = await http.get(
        Uri.parse('http://192.168.6.214:4000/api/usage/daily-history/$_userId'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> history = jsonDecode(response.body);
        List<BarChartGroupData> groups = [];

        for (var entry in history) {
          groups.add(
            BarChartGroupData(
              x: entry['day'],
              barRods: [
                BarChartRodData(
                  toY: (entry['kwh'] ?? 0.0).toDouble(),
                  color: Colors.cyanAccent,
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
                )
              ],
            ),
          );
        }
        setState(() => _barGroups = groups);
      }
    } catch (e) {
      debugPrint("Bar chart fetch error: $e");
    }
  }

  double _calculateBill(double usage) => _baseCharge + (usage * _electricityRate);

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/bill-prediction',
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💰 Bill Predictor', 
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 20),
                _buildMainPredictionCard(),
                const SizedBox(height: 20),
                _buildMonthlyComparisonRow(),
                const SizedBox(height: 30),
                const Text('📊 Daily Consumption History (kWh)', 
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                _buildUsageBarChart(),
                const SizedBox(height: 30),
                _buildAnomalyStatusCard(),
                const SizedBox(height: 20),
                _buildInfoSection(),
              ],
            ),
          ),
    );
  }

  Widget _buildMainPredictionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF1A1A3A), Color(0xFF0A0A2A)]),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Text('Predicted Bill for this month', style: TextStyle(color: Colors.white70)),
          Text('₹${_predictedMonthlyBill.toStringAsFixed(2)}', 
            style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)),
          Text('Expected Usage: ${_predictedMonthlyUsage.toStringAsFixed(1)} kWh', 
            style: const TextStyle(color: Colors.cyanAccent)),
        ],
      ),
    );
  }

  Widget _buildMonthlyComparisonRow() {
    return Row(
      children: [
        Expanded(child: _statCard("This Month", "${_currentMonthUsage.toStringAsFixed(1)} kWh", Colors.blue)),
        const SizedBox(width: 15),
        Expanded(child: _statCard("Last Month", "${_lastMonthUsage.toStringAsFixed(1)} kWh", Colors.orange)),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildUsageBarChart() {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: _barGroups.isEmpty 
        ? const Center(child: Text("Loading history data...", style: TextStyle(color: Colors.white54)))
        : BarChart(
            BarChartData(
              barGroups: _barGroups,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, 
                    reservedSize: 30, 
                    getTitlesWidget: (value, _) => Text(
                      "${value.toInt()}", 
                      style: const TextStyle(color: Colors.white54, fontSize: 10)
                    )
                  )
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) => Text(
                      "D${value.toInt()}", 
                      style: const TextStyle(color: Colors.white54, fontSize: 10)
                    )
                  )
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${rod.toY.toStringAsFixed(2)} kWh',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    );
                  },
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildAnomalyStatusCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _riskColor.withOpacity(0.1),
        border: Border.all(color: _riskColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(15)
      ),
      child: Row(
        children: [
          Icon(Icons.insights, color: _riskColor),
          const SizedBox(width: 15),
          Text("Pattern Check: $_riskLevel", 
            style: TextStyle(color: _riskColor, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(15)),
      child: const Text(
        "Note: Predictions are based on your usage history from the database. Data resets automatically on the 1st of every month.",
        style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
      ),
    );
  }
}