import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../utils/responsive_scaffold.dart';
import '../services/api_service.dart';

class BillPredictionScreen extends StatefulWidget {
  const BillPredictionScreen({super.key});

  @override
  State<BillPredictionScreen> createState() => _BillPredictionScreenState();
}

class _BillPredictionScreenState extends State<BillPredictionScreen> {
  String? _userId;
  bool _isLoading = true;
  String? _errorMessage;

  // Monthly Analytics Data
  double _currentMonthUsage = 0.0;
  double _lastMonthUsage = 0.0;
  double _predictedMonthlyUsage = 0.0;
  double _predictedMonthlyBill = 0.0;
  double _lastMonthBill = 0.0;
  double _electricityRate = 10.0;
  double _baseCharge = 50.0;

  String _riskLevel = 'Normal';
  Color _riskColor = Colors.green;

  // Daily usage bar data for current month (1..today)
  List<BarChartGroupData> _dailyBarGroups = [];
  double _maxDailyUsageKwh = 1.0;

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
    if (userJson == null) {
      setState(() {
        _userId = null;
        _isLoading = false;
        _errorMessage = 'Please log in to view bill prediction.';
      });
      return;
    }

    try {
      final user = jsonDecode(userJson);
      final dynamic id = user['id'];
      if (id == null) {
        setState(() {
          _userId = null;
          _isLoading = false;
          _errorMessage = 'User id missing. Please log in again.';
        });
        return;
      }

      setState(() {
        _userId = id.toString();
        _errorMessage = null;
      });
      await _fetchBillPredictionData();
    } catch (e) {
      setState(() {
        _userId = null;
        _isLoading = false;
        _errorMessage = 'Could not read user session. Please log in again.';
      });
    }
  }

  Future<void> _fetchBillPredictionData() async {
    if (_userId == null) return;
    setState(() => _isLoading = true);

    try {
      setState(() => _errorMessage = null);
      // 1) Fetch current billing from DB-backed endpoint
      final billResponse = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/billing/current/$_userId'),
          )
          .timeout(ApiService.connectionTimeout);

      if (billResponse.statusCode == 200) {
        final billData = jsonDecode(billResponse.body);

        if (billData['success'] && billData['billing'] != null) {
          final now = DateTime.now();
          final daysElapsed = now.day;
          final totalDaysInMonth = DateTime(now.year, now.month + 1, 0).day;

          final usageToDate = double.tryParse(
                billData['billing']['total_units_kwh'].toString(),
              ) ??
              0.0;
          final currentBill = double.tryParse(
                billData['billing']['slab_bill_rs'].toString(),
              ) ??
              0.0;

          final rate = double.tryParse(
                billData['billing']['rate_per_kwh']?.toString() ?? '',
              ) ??
              _electricityRate;
          final baseCharge = double.tryParse(
                billData['billing']['base_charge_rs']?.toString() ?? '',
              ) ??
              _baseCharge;

          final avgDailyUsage =
              daysElapsed > 0 ? usageToDate / daysElapsed : 0.0;
          final predictedUsage = avgDailyUsage * totalDaysInMonth;

          // Prefer tariff-based projection when tariff fields are available,
          // otherwise scale current bill by day ratio.
          double projectedBill;
          if (billData['billing']['rate_per_kwh'] != null ||
              billData['billing']['base_charge_rs'] != null) {
            projectedBill = baseCharge + (predictedUsage * rate);
          } else {
            projectedBill = daysElapsed > 0
                ? currentBill * (totalDaysInMonth / daysElapsed)
                : currentBill;
          }

          setState(() {
            _currentMonthUsage = usageToDate;
            _predictedMonthlyUsage = predictedUsage;
            _predictedMonthlyBill = projectedBill;
            _electricityRate = rate;
            _baseCharge = baseCharge;
            _riskLevel = 'Normal';
            _riskColor = Colors.green;
          });
          debugPrint(
              '✅ Billing data loaded: Usage=${_currentMonthUsage}kWh, CurrentBill=₹$currentBill, Projected=₹$_predictedMonthlyBill');
        } else {
          setState(() {
            _errorMessage =
                billData['message']?.toString() ?? 'No billing data found yet.';
          });
        }
      } else {
        // Fallback to manual calculation if billing view fails
        debugPrint('⚠️ Billing endpoint returned ${billResponse.statusCode}');
        await _fetchSummaryDataFallback();
      }

      // 2) Fetch current-month daily usage (DB) for bar chart
      await _fetchDailyHistory();

      // Keep displayed current-month usage aligned with Dashboard goal progress.
      await _syncCurrentUsageWithGoalProgress();

      // 3) Fetch previous month bill amount from DB history
      await _fetchLastMonthBill();

      // 4) Check usage summary for anomaly demo (strong spike detection)
      try {
        final summaryResp = await http
            .get(
              Uri.parse('${ApiService.baseUrl}/usage/summary/$_userId'),
            )
            .timeout(ApiService.connectionTimeout);

        if (summaryResp.statusCode == 200) {
          final summary = jsonDecode(summaryResp.body);
          setState(() {
            _lastMonthUsage =
                double.tryParse(summary['lastMonthKwh']?.toString() ?? '0') ??
                    _lastMonthUsage;
            if (_lastMonthBill <= 0 && _lastMonthUsage > 0) {
              _lastMonthBill =
                  _baseCharge + (_lastMonthUsage * _electricityRate);
            }
          });

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
      setState(() {
        _errorMessage =
            'Failed to load bill prediction. Check backend connection.';
      });
      // Fallback if billing fetch fails
      try {
        await _fetchSummaryDataFallback();
        await _fetchDailyHistory();
        await _fetchLastMonthBill();
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
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/usage/summary/$_userId'),
          )
          .timeout(ApiService.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          // Use double.tryParse for safe numeric conversions
          _currentMonthUsage =
              double.tryParse(data['currentMonthKwh'].toString()) ?? 0.0;
          _lastMonthUsage =
              double.tryParse(data['lastMonthKwh'].toString()) ?? 0.0;

          int daysPassed = (data['daysElapsed'] as int?) ?? 1;
          double dailyRate =
              _currentMonthUsage / (daysPassed > 0 ? daysPassed : 1);
          _predictedMonthlyUsage = dailyRate * 30;
          _predictedMonthlyBill =
              _baseCharge + (_predictedMonthlyUsage * _electricityRate);
          _lastMonthBill = _baseCharge + (_lastMonthUsage * _electricityRate);

          // Check for abnormal usage flag
          if (data['isAbnormal'] == true) {
            final socketName = data['anomalySocket'] ?? 'Unknown Socket';
            _riskLevel = '⚠️ CRITICAL: ABNORMAL LOAD';
            _riskColor = Colors.red;

            // Show high-visibility alert dialog
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showAnomalyAlert(socketName);
            });

            final currentPower =
                double.tryParse(data['currentPower'].toString()) ?? 0.0;
            final avgPower =
                double.tryParse(data['historicalAvgPower'].toString()) ?? 0.0;

            debugPrint(
                '🚨 ABNORMAL USAGE: Current ${currentPower}W vs Avg ${avgPower}W | Source: $socketName');
          } else {
            double historicalAvg =
                double.tryParse(data['historicalAvgPower'].toString()) ?? 0.0;
            if (historicalAvg > 0 &&
                (dailyRate / 24) > (historicalAvg / 1000) * 1.5) {
              _riskLevel = '⚠️ High Usage Detected';
              _riskColor = Colors.orange;
            } else {
              _riskLevel = 'Normal';
              _riskColor = Colors.green;
            }
          }

          debugPrint(
              '✅ Summary data loaded: Usage=${_currentMonthUsage}kWh, Risk=$_riskLevel');
        });
      }
    } catch (e) {
      debugPrint('❌ Fallback Summary Error: $e');
    }
  }

  Future<void> _syncCurrentUsageWithGoalProgress() async {
    if (_userId == null) return;

    try {
      final progressRes = await ApiService.getGoalProgress(int.parse(_userId!));
      if (progressRes['success'] != true || progressRes['progress'] == null) {
        return;
      }

      final progress = progressRes['progress'] as Map<String, dynamic>;
      final unifiedUsage = double.tryParse(
              progress['monthly']?['currentUsage']?.toString() ?? '0') ??
          _currentMonthUsage;

      if (unifiedUsage < 0) return;

      final now = DateTime.now();
      final daysElapsed = now.day;
      final totalDaysInMonth = DateTime(now.year, now.month + 1, 0).day;
      final avgDailyUsage = daysElapsed > 0 ? unifiedUsage / daysElapsed : 0.0;
      final predictedUsage = avgDailyUsage * totalDaysInMonth;
      final projectedBill = _baseCharge + (predictedUsage * _electricityRate);

      setState(() {
        _currentMonthUsage = unifiedUsage;
        _predictedMonthlyUsage = predictedUsage;
        _predictedMonthlyBill = projectedBill;
      });
    } catch (e) {
      debugPrint('⚠️ Goal progress usage sync failed: $e');
    }
  }

  Future<void> _fetchLastMonthBill() async {
    if (_userId == null) return;

    try {
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/billing/history/$_userId'),
          )
          .timeout(ApiService.connectionTimeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> bills = (data['bills'] as List<dynamic>? ?? []);
        final String currentPeriod = _periodLabel(DateTime.now());

        Map<String, dynamic>? previousMonthEntry;
        for (final entry in bills) {
          if ((entry['period']?.toString() ?? '') != currentPeriod) {
            previousMonthEntry = Map<String, dynamic>.from(entry as Map);
            break;
          }
        }

        if (previousMonthEntry != null) {
          final amount = double.tryParse(
                previousMonthEntry['amount'].toString(),
              ) ??
              0.0;
          setState(() => _lastMonthBill = amount);
          return;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Last month bill fetch failed: $e');
    }

    // Fallback: derive from last month kWh + current tariff
    setState(() {
      _lastMonthBill = _baseCharge + (_lastMonthUsage * _electricityRate);
    });
  }

  String _periodLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.year}';
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
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w500),
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
                  "",
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
              style:
                  TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
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
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        // Turn off both relays via backend
        final host = ApiService.baseUrl.replaceFirst('/api', '');
        await http
            .get(Uri.parse('$host/api/relay/relay1/off'))
            .timeout(ApiService.connectionTimeout);
        await http
            .get(Uri.parse('$host/api/relay/relay2/off'))
            .timeout(ApiService.connectionTimeout);

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

      final host = ApiService.baseUrl.replaceFirst('/api', '');
      final response = await http
          .get(
            Uri.parse('$host$endpoint'),
          )
          .timeout(ApiService.connectionTimeout);

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
    final int today = DateTime.now().day;

    final Map<int, double> dayToKwh = {
      for (int day = 1; day <= today; day++) day: 0.0,
    };

    try {
      final response = await http
          .get(
            Uri.parse('${ApiService.baseUrl}/usage/daily-history/$_userId'),
          )
          .timeout(ApiService.connectionTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> history = jsonDecode(response.body);

        for (final raw in history) {
          final entry = Map<String, dynamic>.from(raw as Map);
          final day = int.tryParse(entry['day'].toString()) ?? 0;
          final kwh = double.tryParse(entry['kwh'].toString()) ?? 0.0;
          if (day >= 1 && day <= today) {
            dayToKwh[day] = kwh;
          }
        }
      }

      final List<BarChartGroupData> groups = [];
      double maxDaily = 0.0;

      dayToKwh.forEach((day, kwh) {
        if (kwh > maxDaily) maxDaily = kwh;
        groups.add(
          BarChartGroupData(
            x: day,
            barRods: [
              BarChartRodData(
                toY: kwh,
                color: Colors.cyanAccent,
                width: 7,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        );
      });

      setState(() {
        _dailyBarGroups = groups;
        _maxDailyUsageKwh = maxDaily > 0 ? maxDaily * 1.2 : 1.0;
      });
    } catch (e) {
      debugPrint("Line chart fetch error: $e");
      // Still render month-to-date empty bars so chart UI is visible.
      final groups = List<BarChartGroupData>.generate(today, (index) {
        final day = index + 1;
        return BarChartGroupData(
          x: day,
          barRods: [
            BarChartRodData(
              toY: 0,
              color: Colors.cyanAccent,
              width: 7,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        );
      });

      setState(() {
        _dailyBarGroups = groups;
        _maxDailyUsageKwh = 1.0;
      });
    }
  }

  double _calculateBill(double usage) =>
      _baseCharge + (usage * _electricityRate);

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/bill-prediction',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_userId == null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _errorMessage ?? 'Please log in to continue.',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💰 Bill Predictor',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const SizedBox(height: 20),
                      Text(
                        'User: ${_userId ?? '-'}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      if (_errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.red.withOpacity(0.35)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildMainPredictionCard(),
                      const SizedBox(height: 20),
                      _buildMonthlyComparisonRow(),
                      const SizedBox(height: 30),
                      const Text('📊 Daily Usage (Current Month)',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      _buildDailyUsageBarChart(),
                      const SizedBox(height: 30),
                      _buildLastMonthBillCard(),
                      const SizedBox(height: 20),
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
        gradient: const LinearGradient(
            colors: [Color(0xFF1A1A3A), Color(0xFF0A0A2A)]),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Text('Predicted Bill for this month',
              style: TextStyle(color: Colors.white70)),
          Text('₹${_predictedMonthlyBill.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(
              'Expected Usage: ${_predictedMonthlyUsage.toStringAsFixed(1)} kWh',
              style: const TextStyle(color: Colors.cyanAccent)),
        ],
      ),
    );
  }

  Widget _buildMonthlyComparisonRow() {
    return Row(
      children: [
        Expanded(
            child: _statCard("This Month",
                "${_currentMonthUsage.toStringAsFixed(1)} kWh", Colors.blue)),
        const SizedBox(width: 15),
        Expanded(
            child: _statCard("Last Month Bill",
                "₹${_lastMonthBill.toStringAsFixed(2)}", Colors.orange)),
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
          Text(label,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 5),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDailyUsageBarChart() {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: _dailyBarGroups.isEmpty
          ? const Center(
              child: Text(
                "No daily usage data yet for this month.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            )
          : BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _maxDailyUsageKwh,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _maxDailyUsageKwh <= 5 ? 1 : null,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) {
                            if (value < 0) return const SizedBox.shrink();
                            return Text(value.toStringAsFixed(1),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10));
                          })),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() % 5 != 0 &&
                                _dailyBarGroups.length > 12) {
                              return const SizedBox.shrink();
                            }
                            return Text(value.toInt().toString(),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10));
                          })),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        'Day ${group.x}: ${rod.toY.toStringAsFixed(2)} kWh',
                        const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                barGroups: _dailyBarGroups,
              ),
            ),
    );
  }

  Widget _buildLastMonthBillCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Last Month Bill',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            '₹${_lastMonthBill.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.orangeAccent,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomalyStatusCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: _riskColor.withOpacity(0.1),
          border: Border.all(color: _riskColor.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(15)),
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
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(15)),
      child: const Text(
        "Note: Predictions are based on your usage history from the database. Data resets automatically on the 1st of every month.",
        style: TextStyle(
            color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
      ),
    );
  }
}
