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
  String userEmail = "user@example.com";
  String consumerNumber = "N/A";

  // ---------------- ESP32 DATA ----------------
  Map<String, dynamic>? esp32Data;
  Timer? _refreshTimer;



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
        userEmail = user['email'] ?? 'user@example.com';
        consumerNumber = user['consumer_number'] ?? 'N/A';
      });
    }
  }

  // ---------------- LOAD ESP32 DATA ----------------
  Future<void> _loadEsp32Data() async {
    try {
      final response = await http.get(
        Uri.parse('http://192.168.6.214:4000/esp32/latest'),
      );

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

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/dashboard',
      body: RefreshIndicator(
        onRefresh: _loadEsp32Data,
        color: Colors.cyanAccent,
        backgroundColor: const Color(0xFF1A1A3A),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER with Refresh Button
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
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.cyanAccent, width: 1),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.cyanAccent, size: 28),
                      onPressed: _loadEsp32Data,
                      tooltip: 'Pull down to refresh or tap here',
                      iconSize: 28,
                    ),
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
                      esp32Data?['power']?.toStringAsFixed(1) ?? '2.45',
                      "W",
                      Icons.flash_on,
                    ),
                    _metricCard(
                      "Voltage",
                      esp32Data?['voltage']?.toString() ?? '230',
                      "V",
                      Icons.electric_bolt,
                    ),
                    _metricCard(
                      "Current",
                      esp32Data?['current']?.toString() ?? '1.2',
                      "A",
                      Icons.trending_up,
                    ),
                    _metricCard(
                      "Energy Used",
                      esp32Data?['energy']?.toString() ?? '125.5',
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


