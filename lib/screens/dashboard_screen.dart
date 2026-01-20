import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../utils/responsive_scaffold.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String username = "User";

  // ---------------- ESP32 DATA ----------------
  Map<String, dynamic>? esp32Data;
  Timer? _refreshTimer;
  
  // ---------------- STATIC DATA (UNCHANGED) ----------------
  final List<double> monthlyUsage = [110, 130, 145, 140, 155, 135, 124];
  final List<String> months = ['Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'];

  final List<Map<String, dynamic>> recentBills = [
    {'period': "Oct-Nov '25", 'amount': 925.50, 'status': 'paid'},
    {'period': "Sep-Oct '25", 'amount': 870.50, 'status': 'due'},
    {'period': "Aug-Sep '25", 'amount': 795.00, 'status': 'paid'},
    {'period': "Jul-Aug '25", 'amount': 910.20, 'status': 'paid'},
    {'period': "Jun-Jul '25", 'amount': 850.75, 'status': 'paid'},
  ];

  // ---------------- INIT ----------------
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadEsp32Data();

    _refreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _loadEsp32Data());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ---------------- LOAD USER ----------------
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString('wattBuddyUser');
    if (storedUser != null) {
      final user = jsonDecode(storedUser);
      setState(() {
        username = user['username'] ?? 'User';
      });
    }
  }

  // ---------------- LOAD ESP32 DATA ----------------
  Future<void> _loadEsp32Data() async {
    try {
      final response = await http.get(
        Uri.parse('http://192.168.233.214:4000/api/esp32/latest'),
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        setState(() {
          esp32Data = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('❌ ESP32 fetch error: \$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/dashboard',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            const Text(
              "Dashboard",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Welcome back, \$username! Here's your energy overview.",
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),

            const SizedBox(height: 30),

            // METRIC CARDS (LIVE DATA)
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
                  childAspectRatio:
                      MediaQuery.of(context).size.width < 600 ? 3.0 : 3.8,
                  children: [
                    _metricCard(
                      "Current Power",
                      esp32Data?['power']?.toStringAsFixed(1) ?? '--',
                      "W",
                      Icons.flash_on,
                    ),
                    _metricCard(
                      "Voltage",
                      esp32Data?['voltage']?.toString() ?? '--',
                      "V",
                      Icons.electric_bolt,
                    ),
                    _metricCard(
                      "Current",
                      esp32Data?['current']?.toString() ?? '--',
                      "A",
                      Icons.trending_up,
                    ),
                    _metricCard(
                      "Energy Used",
                      esp32Data?['energy']?.toString() ?? '--',
                      "kWh",
                      Icons.battery_charging_full,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 30),

            // CHART + BILLS (UNCHANGED)
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    children: [
                      _usageChart(),
                      const SizedBox(height: 20),
                      _recentBillsCard(),
                    ],
                  );
                } else {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _usageChart()),
                      const SizedBox(width: 20),
                      Expanded(child: _recentBillsCard()),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ------------------ METRIC CARD ------------------
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
                "\$value \$unit",
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

  // ------------------ CHART (UNCHANGED) ------------------
  Widget _usageChart() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Monthly Usage (kWh)",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: isMobile ? 200 : 260,
            child: LineChart(
              LineChartData(
                minY: 100,
                maxY: 160,
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        if (value.toInt() < months.length) {
                          return Text(
                            months[value.toInt()],
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: monthlyUsage
                        .asMap()
                        .entries
                        .map(
                          (e) => FlSpot(e.key.toDouble(), e.value),
                        )
                        .toList(),
                    isCurved: true,
                    color: Colors.cyanAccent,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.cyan.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------ RECENT BILLS (UNCHANGED) ------------------
  Widget _recentBillsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Recent Bills",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...recentBills.map((bill) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bill['period'],
                      style: const TextStyle(color: Colors.white70)),
                  Text(
                    "₹\${bill['amount']}",
                    style: TextStyle(
                      color: bill['status'] == 'paid'
                          ? Colors.green
                          : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
