import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';

import '../utils/responsive_scaffold.dart';
import '../services/bill_history_service.dart';

class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  _BillHistoryScreenState createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  List<Map<String, dynamic>> bills = []; // will be populated from API
  bool _isLoading = true;
  String? _errorMessage;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserAndBills();
  }

  Future<void> _loadUserAndBills() async {
    // reuse logic similar to prediction screen to get stored user id
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('wattBuddyUser');
      if (userJson == null) throw Exception('no session');
      final user = jsonDecode(userJson);
      final id = user['id'];
      if (id == null) throw Exception('missing id');
      setState(() {
        _userId = id.toString();
      });
      await _fetchBillHistory();
    } catch (e) {
      setState(() {
        _errorMessage = 'Unable to load user session.';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchBillHistory() async {
    if (_userId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await BillHistoryService.getHistory(_userId!);
      if (data.isEmpty) {
        setState(() {
          _errorMessage = 'No bill history available';
          bills = [];
        });
      } else {
        setState(() {
          bills = data;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch bill history';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/bills',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            const Text(
              "Bill History",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "View and manage your electricity bills",
              style: TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 30),

            // FETCH STATES
            if (_isLoading) const Center(child: CircularProgressIndicator()),
            if (!_isLoading && _errorMessage != null)
              Center(
                child: Text(_errorMessage!,
                    style: const TextStyle(color: Colors.white70)),
              ),

            // If we have data show graph + table/cards
            if (!_isLoading && _errorMessage == null && bills.isNotEmpty) ...[
              // simple bar chart comparing bill amounts
              _historyChart(),
              const SizedBox(height: 30),

              // RESPONSIVE CONTENT
              LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth < 700) {
                    // 📱 MOBILE → CARD LIST
                    return Column(
                        children: bills.map(_mobileBillCard).toList());
                  } else {
                    // 💻 DESKTOP → TABLE
                    return _desktopTable();
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- DESKTOP TABLE ----------------

  Widget _desktopTable() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          _tableHeader(),
          const Divider(color: Colors.white24),
          ...bills.map(_tableRow),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    return Row(
      children: const [
        HeaderCell("Period"),
        HeaderCell("Due Date"),
        HeaderCell("Amount"),
        HeaderCell("Units"),
        HeaderCell("Status"),
      ],
    );
  }

  Widget _tableRow(Map<String, dynamic> bill) {
    final paid = bill['status'] == 'paid';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Cell(bill['period']),
          Cell(bill['dueDate']),
          Cell("₹${bill['amount']}"),
          Cell("${bill['units']}"),
          StatusCell(paid),
        ],
      ),
    );
  }

  // ---------------- MOBILE CARD ----------------

  Widget _mobileBillCard(Map<String, dynamic> bill) {
    final paid = bill['status'] == 'paid';

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bill['period'],
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _infoRow("Due Date", bill['dueDate']),
          _infoRow("Units", "${bill['units']} kWh"),
          _infoRow("Amount", "₹${bill['amount']}"),
          const SizedBox(height: 10),
          _statusChip(paid),
        ],
      ),
    );
  }

  // ---------------- HELPERS ----------------

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text("$label: ", style: const TextStyle(color: Colors.white70)),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _statusChip(bool paid) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: paid
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: paid ? Colors.green : Colors.orange),
      ),
      child: Text(
        paid ? "Paid" : "Due",
        style: TextStyle(
          color: paid ? Colors.green : Colors.orange,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // --------- CHART ----------

  Widget _historyChart() {
    // show bar chart of amounts
    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < bills.length; i++) {
      final amount = (bills[i]['amount'] as num?)?.toDouble() ?? 0.0;
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: amount, color: Colors.cyanAccent)],
      ));
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: BarChart(
        BarChartData(
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, interval: 200),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() < 0 || value.toInt() >= bills.length) {
                    return const SizedBox.shrink();
                  }
                  final label = bills[value.toInt()]['period'] ?? '';
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      label.toString().split(' ').first,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
}

// ---------------- SMALL WIDGETS ----------------

class HeaderCell extends StatelessWidget {
  final String text;
  const HeaderCell(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class Cell extends StatelessWidget {
  final String text;
  const Cell(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

class StatusCell extends StatelessWidget {
  final bool paid;
  const StatusCell(this.paid, {super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(child: StatusChip(paid));
  }
}

class StatusChip extends StatelessWidget {
  final bool paid;
  const StatusChip(this.paid, {super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: paid
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.orange.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: paid ? Colors.green : Colors.orange),
        ),
        child: Text(
          paid ? "Paid" : "Due",
          style: TextStyle(
            color: paid ? Colors.green : Colors.orange,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
