import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../utils/responsive_scaffold.dart';
import '../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String username = "User";
  String userEmail = "user@example.com";
  String consumerNumber = "N/A";
  int? userId;

  // ESP32 DATA
  Map<String, dynamic>? esp32Data;
  Timer? _refreshTimer;

  // GOAL TRACKING STATE
  bool isLoadingGoals = true;
  Map<String, dynamic>? goalProgress;
  double dailyLimitKwh = 0.0;
  double monthlyLimitKwh = 0.0;
  double dailyUsageKwh = 0.0;
  double monthlyUsageKwh = 0.0;
  double carriedOverKwh = 0.0;
  double totalAvailableKwh = 0.0;
  double dailyRemainingKwh = 0.0;
  double monthlyRemainingKwh = 0.0;
  bool dailyExceeded = false;
  bool monthlyExceeded = false;
  bool carryForwardEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadEsp32Data();
    _loadGoalProgress();

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _loadEsp32Data();
      _loadGoalProgress();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString('wattBuddyUser');
    if (storedUser != null) {
      final user = jsonDecode(storedUser);
      setState(() {
        username = user['username'] ?? 'User';
        userEmail = user['email'] ?? 'user@example.com';
        consumerNumber = user['consumer_number'] ?? 'N/A';
        userId = user['id'];
      });
      // Load goals after we have userId
      if (userId != null) {
        _loadGoalProgress();
        // Keep ESP32 telemetry mapped to the active app user.
        final ok = await ApiService.setESP32User(userId.toString());
        if (ok) {
          debugPrint('✅ Dashboard provisioned ESP32 user: $userId');
        } else {
          debugPrint('⚠️ Dashboard could not provision ESP32 user');
        }
      }
    }
  }

  Future<void> _loadEsp32Data() async {
    try {
      final host = ApiService.baseUrl.replaceFirst('/api', '');
      final response = await http
          .get(
            Uri.parse('$host/esp32/latest'),
          )
          .timeout(ApiService.connectionTimeout);

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          setState(() {
            esp32Data = responseData['data'];
          });
        }
      }
    } catch (e) {
      debugPrint('❌ ESP32 fetch error: $e');
    }
  }

  Future<void> _loadGoalProgress() async {
    if (userId == null) return;

    setState(() => isLoadingGoals = true);

    try {
      final response = await ApiService.getGoalProgress(userId!);

      if (response['success'] == true) {
        final progress = response['progress'];
        setState(() {
          // Daily progress
          dailyUsageKwh = (progress['daily']['currentUsage'] ?? 0).toDouble();
          dailyLimitKwh = (progress['daily']['dailyLimit'] ?? 0).toDouble();
          carriedOverKwh = (progress['daily']['carriedOver'] ?? 0).toDouble();
          totalAvailableKwh =
              (progress['daily']['totalAvailable'] ?? 0).toDouble();
          dailyRemainingKwh = (progress['daily']['remaining'] ?? 0).toDouble();
          dailyExceeded = progress['daily']['exceeded'] ?? false;

          // Monthly progress
          monthlyUsageKwh =
              (progress['monthly']['currentUsage'] ?? 0).toDouble();
          monthlyLimitKwh =
              (progress['monthly']['monthlyLimit'] ?? 0).toDouble();
          monthlyRemainingKwh =
              (progress['monthly']['remaining'] ?? 0).toDouble();
          monthlyExceeded = progress['monthly']['exceeded'] ?? false;

          carryForwardEnabled = progress['carryForwardEnabled'] ?? true;
          goalProgress = progress;
          isLoadingGoals = false;
        });

        debugPrint(
            '✅ Goal progress loaded: Daily ${dailyUsageKwh.toStringAsFixed(2)} / ${totalAvailableKwh.toStringAsFixed(2)} kWh');
      }
    } catch (e) {
      debugPrint('❌ Goal progress fetch error: $e');
      setState(() => isLoadingGoals = false);
    }
  }

  void _showGoalSettingsDialog() {
    final dailyController = TextEditingController(
      text: dailyLimitKwh > 0 ? dailyLimitKwh.toStringAsFixed(2) : '5.00',
    );
    final monthlyController = TextEditingController(
      text: monthlyLimitKwh > 0 ? monthlyLimitKwh.toStringAsFixed(2) : '150.00',
    );
    bool enableCarryForward = carryForwardEnabled;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A3A),
          title: const Text(
            '⚡ Set Energy Goals',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set daily and monthly consumption limits',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 20),

                TextField(
                  controller: dailyController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Daily Limit (kWh)',
                    labelStyle: TextStyle(color: Colors.cyanAccent),
                    hintText: 'e.g., 5.0',
                    hintStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.cyanAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.cyanAccent, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: monthlyController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Monthly Limit (kWh)',
                    labelStyle: TextStyle(color: Colors.cyanAccent),
                    hintText: 'e.g., 150.0',
                    hintStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.cyanAccent),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.cyanAccent, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Carry Forward Toggle
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyanAccent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Enable Carry Forward',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Switch(
                            value: enableCarryForward,
                            onChanged: (value) {
                              setDialogState(() => enableCarryForward = value);
                            },
                            activeColor: Colors.cyanAccent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'When enabled, unused daily energy carries forward to the next day. If you use more than your limit, no carry forward occurs.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Example Scenario
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.lightbulb, color: Colors.green, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Example:',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Limit: 5 kWh/day\n'
                        'Day 1: Used 3 kWh → 2 kWh carried forward\n'
                        'Day 2: Available 7 kWh (5+2)\n'
                        'Day 2: Used 6 kWh → Still under limit! ✅',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final daily = double.tryParse(dailyController.text) ?? 5.0;
                final monthly =
                    double.tryParse(monthlyController.text) ?? 150.0;

                if (daily <= 0 || monthly <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Limits must be greater than 0'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                await _saveGoals(daily, monthly, enableCarryForward);
              },
              child: const Text(
                'Save Goals',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveGoals(
      double daily, double monthly, bool carryForward) async {
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ User not logged in'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final response = await ApiService.setGoals(
        userId: userId!,
        dailyLimitKwh: daily,
        monthlyLimitKwh: monthly,
        carryForwardEnabled: carryForward,
      );

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Goals saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Reload goal progress
        await _loadGoalProgress();
      } else {
        throw Exception(response['message'] ?? 'Failed to save goals');
      }
    } catch (e) {
      debugPrint('❌ Save goals error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Failed to save goals: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/dashboard',
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadEsp32Data();
          await _loadGoalProgress();
        },
        color: Colors.cyanAccent,
        backgroundColor: const Color(0xFF1A1A3A),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Dashboard",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.cyanAccent, width: 1),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.tune,
                              color: Colors.cyanAccent, size: 24),
                          onPressed: _showGoalSettingsDialog,
                          tooltip: 'Set Goals',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.cyanAccent, width: 1),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.refresh,
                              color: Colors.cyanAccent, size: 28),
                          onPressed: () async {
                            await _loadEsp32Data();
                            await _loadGoalProgress();
                          },
                          tooltip: 'Refresh',
                          iconSize: 28,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Welcome back, $username! Here's your energy overview.",
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 20),

              // USER DETAILS CARD
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.cyanAccent,
                      child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0A0A2A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            userEmail,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Consumer #: $consumerNumber',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // GOAL PROGRESS SECTION
              if (!isLoadingGoals && dailyLimitKwh > 0) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Energy Goals",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (carryForwardEnabled && carriedOverKwh > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.trending_up,
                                color: Colors.green, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '+${carriedOverKwh.toStringAsFixed(2)} kWh carried',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // DAILY GOAL CARD
                _buildGoalCard(
                  title: 'Daily Goal',
                  currentUsage: dailyUsageKwh,
                  limit: dailyLimitKwh,
                  carriedOver: carriedOverKwh,
                  totalAvailable: totalAvailableKwh,
                  remaining: dailyRemainingKwh,
                  exceeded: dailyExceeded,
                  showCarryForward: carryForwardEnabled,
                  icon: Icons.today,
                  color: Colors.cyanAccent,
                ),
                const SizedBox(height: 16),

                // MONTHLY GOAL CARD
                _buildGoalCard(
                  title: 'Monthly Goal',
                  currentUsage: monthlyUsageKwh,
                  limit: monthlyLimitKwh,
                  remaining: monthlyRemainingKwh,
                  exceeded: monthlyExceeded,
                  showCarryForward: false,
                  icon: Icons.calendar_month,
                  color: Colors.purpleAccent,
                ),
                const SizedBox(height: 30),
              ] else if (isLoadingGoals) ...[
                const Center(
                  child: CircularProgressIndicator(color: Colors.cyanAccent),
                ),
                const SizedBox(height: 30),
              ] else ...[
                // NO GOALS SET
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.flag, color: Colors.orange, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'No Goals Set',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Set daily and monthly energy goals to track your usage and save energy with carry forward!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showGoalSettingsDialog,
                        icon: const Icon(Icons.add, color: Colors.black),
                        label: const Text(
                          'Set Goals Now',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],

              // LIVE METRICS
              const Text(
                "Live Metrics",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 4;
                  if (constraints.maxWidth < 1200) crossAxisCount = 2;
                  if (constraints.maxWidth < 600) crossAxisCount = 1;

                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    // Keep cards tall enough for 2 text lines + icon across breakpoints.
                    childAspectRatio:
                        MediaQuery.of(context).size.width < 600 ? 2.4 : 2.2,
                    children: [
                      _metricCard(
                        "Current Power",
                        esp32Data?['power']?.toStringAsFixed(1) ?? '0.0',
                        "W",
                        Icons.flash_on,
                      ),
                      _metricCard(
                        "Voltage",
                        esp32Data?['voltage']?.toString() ?? '0',
                        "V",
                        Icons.electric_bolt,
                      ),
                      _metricCard(
                        "Current",
                        esp32Data?['current']?.toString() ?? '0.0',
                        "A",
                        Icons.trending_up,
                      ),
                      _metricCard(
                        "Energy Used",
                        esp32Data?['energy']?.toString() ?? '0.0',
                        "kWh",
                        Icons.battery_charging_full,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoalCard({
    required String title,
    required double currentUsage,
    required double limit,
    double carriedOver = 0.0,
    double totalAvailable = 0.0,
    required double remaining,
    required bool exceeded,
    required bool showCarryForward,
    required IconData icon,
    required Color color,
  }) {
    final percentage = limit > 0
        ? (currentUsage / (showCarryForward ? totalAvailable : limit) * 100)
            .clamp(0, 100)
        : 0.0;
    final effectiveLimit = showCarryForward ? totalAvailable : limit;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: exceeded ? Colors.red : color,
          width: exceeded ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: exceeded
                      ? Colors.red.withOpacity(0.2)
                      : Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: exceeded ? Colors.red : Colors.green,
                  ),
                ),
                child: Text(
                  exceeded ? 'EXCEEDED' : 'ON TRACK',
                  style: TextStyle(
                    color: exceeded ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Usage Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Usage',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${currentUsage.toStringAsFixed(2)} kWh',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Limit',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${effectiveLimit.toStringAsFixed(2)} kWh',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Carry Forward Info
          if (showCarryForward && carriedOver > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.savings, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Carried Forward',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  Text(
                    '+${carriedOver.toStringAsFixed(2)} kWh',
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Base Limit:',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                Text(
                  '${limit.toStringAsFixed(2)} kWh',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 12,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                exceeded ? Colors.red : color,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${percentage.toStringAsFixed(1)}% used',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${remaining.toStringAsFixed(2)} kWh remaining',
                style: TextStyle(
                  color: exceeded ? Colors.red : Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, String unit, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyanAccent, size: 28),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                "$value $unit",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
