import 'package:flutter/material.dart';
import '../utils/responsive_scaffold.dart';

class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  _BillHistoryScreenState createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  final List<Map<String, dynamic>> bills = [
    {
      'period': 'Sep 12 - Oct 12, 2025',
      'dueDate': 'Oct 25, 2025',
      'amount': 870.50,
      'units': 124,
      'status': 'due',
    },
    {
      'period': 'Aug 12 - Sep 12, 2025',
      'dueDate': 'Sep 25, 2025',
      'amount': 795.00,
      'units': 112,
      'status': 'paid',
    },
    {
      'period': 'Jul 12 - Aug 12, 2025',
      'dueDate': 'Aug 25, 2025',
      'amount': 910.20,
      'units': 135,
      'status': 'paid',
    },
    {
      'period': 'Jun 12 - Jul 12, 2025',
      'dueDate': 'Jul 25, 2025',
      'amount': 850.75,
      'units': 121,
      'status': 'paid',
    },
  ];

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

            // RESPONSIVE CONTENT
            LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 700) {
                  // 📱 MOBILE → CARD LIST
                  return Column(children: bills.map(_mobileBillCard).toList());
                } else {
                  // 💻 DESKTOP → TABLE
                  return _desktopTable();
                }
              },
            ),
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
