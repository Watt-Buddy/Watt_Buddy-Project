import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../utils/responsive_scaffold.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  _DevicesScreenState createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final TextEditingController _deviceNameController = TextEditingController();
  final TextEditingController _powerController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  List<Map<String, dynamic>> _devices = [];

  double _totalMonthlyConsumption = 0;
  double _totalMonthlyCost = 0;
  final double _electricityRate = 8.5; // ₹ / kWh

  @override
  void initState() {
    super.initState();
    _quantityController.text = '1';
    _loadDevices();
  }

  // ---------------- DATA ----------------

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('wattBuddyDevices');

    if (stored != null) {
      _devices = List<Map<String, dynamic>>.from(jsonDecode(stored));
      _calculateTotals();
      setState(() {});
    }
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wattBuddyDevices', jsonEncode(_devices));
  }

  void _calculateTotals() {
    _totalMonthlyConsumption = 0;

    for (var d in _devices) {
      final power = d['power'] as num;
      final hours = d['hours'] as num;
      final qty = d['quantity'] as num;
      _totalMonthlyConsumption += (power * hours * qty * 30) / 1000;
    }

    _totalMonthlyCost = _totalMonthlyConsumption * _electricityRate;
  }

  // ---------------- ACTIONS ----------------

  void _addDevice() {
    final name = _deviceNameController.text.trim();
    final power = double.tryParse(_powerController.text) ?? 0;
    final hours = double.tryParse(_hoursController.text) ?? 0;
    final qty = int.tryParse(_quantityController.text) ?? 1;

    if (name.isEmpty || power <= 0 || hours <= 0) {
      _alert("Invalid Input", "Please enter valid values.");
      return;
    }

    final daily = (power * hours * qty) / 1000;
    final monthly = daily * 30;

    setState(() {
      _devices.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'name': name,
        'power': power,
        'hours': hours,
        'quantity': qty,
        'monthlyConsumption': monthly,
        'monthlyCost': monthly * _electricityRate,
      });
      _calculateTotals();
      _saveDevices();
    });

    _deviceNameController.clear();
    _powerController.clear();
    _hoursController.clear();
    _quantityController.text = '1';
  }

  void _deleteDevice(int index) {
    setState(() {
      _devices.removeAt(index);
      _calculateTotals();
      _saveDevices();
    });
  }

  void _alert(String title, String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/devices',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            const Text(
              "Device Management",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Add and track your electrical devices",
              style: TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 30),

            // SUMMARY
            LayoutBuilder(
              builder: (context, c) {
                int cols = c.maxWidth < 800 ? 1 : 3;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: MediaQuery.of(context).size.width < 600
                      ? 2.8
                      : 3.8,
                  children: [
                    _summary("Total Devices", "${_devices.length}"),
                    _summary(
                      "Monthly Usage",
                      "${_totalMonthlyConsumption.toStringAsFixed(1)} kWh",
                    ),
                    _summary(
                      "Estimated Bill",
                      "₹${_totalMonthlyCost.toStringAsFixed(2)}",
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 30),

            // ADD DEVICE
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Add New Device",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _input(_deviceNameController, "Device Name"),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _input(
                          _powerController,
                          "Power (W)",
                          type: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _input(
                          _hoursController,
                          "Hours / day",
                          type: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _input(
                          _quantityController,
                          "Qty",
                          type: TextInputType.number,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _addDevice,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0072FF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Add Device"),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // DEVICE LIST
            if (_devices.isEmpty)
              const Center(
                child: Text(
                  "No devices added yet",
                  style: TextStyle(color: Colors.white70),
                ),
              )
            else
              Column(
                children: _devices.asMap().entries.map((e) {
                  final d = e.value;
                  return _card(
                    child: ListTile(
                      title: Text(
                        d['name'],
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        "${d['monthlyConsumption'].toStringAsFixed(2)} kWh / month",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteDevice(e.key),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- REUSABLE ----------------

  Widget _summary(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16), // 🔽 reduced padding
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            value,
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
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }

  Widget _input(
    TextEditingController c,
    String label, {
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: c,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.blue),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
