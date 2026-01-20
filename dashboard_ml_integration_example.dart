import 'package:flutter/material.dart';
import 'package:watt_buddy/services/ml_service.dart';

class AnomalyAlertWidget extends StatefulWidget {
  final String userId;
  final List<double> powerData;
  final List<double> historicalData;
  final VoidCallback? onAnomalyDetected;

  const AnomalyAlertWidget({
    super.key,
    required this.userId,
    required this.powerData,
    required this.historicalData,
    this.onAnomalyDetected,
  });

  @override
  State<AnomalyAlertWidget> createState() => _AnomalyAlertWidgetState();
}

class _AnomalyAlertWidgetState extends State<AnomalyAlertWidget> {
  List<int> anomalyStatus = [];
  bool hasAnomalies = false;
  int anomalyCount = 0;
  bool isCheckingAnomalies = false;
  Map<String, dynamic> latestAnalysis = {};

  @override
  void initState() {
    super.initState();
    _initAnomalies();
  }

  Future<void> _initAnomalies() async {
    await _detectAnomalies();
    // Check every 30 minutes
    Future.delayed(const Duration(minutes: 30), _initAnomalies);
  }

  Future<void> _detectAnomalies() async {
    if (isCheckingAnomalies) return;

    setState(() => isCheckingAnomalies = true);

    try {
      final result = await MLService.analyzeEnergy(
        userId: widget.userId,
        powerData: widget.powerData,
        historicalData: widget.historicalData,
      );

      if (mounted) {
        setState(() {
          if (result['success']) {
            final anomalies = result['anomalies'] ?? {};
            anomalyStatus = List<int>.from(anomalies['anomalies'] ?? []);
            hasAnomalies = anomalies['is_anomaly'] ?? false;
            anomalyCount =
                anomalies['anomalies']?.where((a) => a == 1).length ?? 0;
            latestAnalysis = result;

            if (hasAnomalies) {
              widget.onAnomalyDetected?.call();
            }
          }
          isCheckingAnomalies = false;
        });
      }
    } catch (e) {
      debugPrint('Error detecting anomalies: $e');
      if (mounted) {
        setState(() => isCheckingAnomalies = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasAnomalies) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent, width: 2),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚠️ Anomalies Detected',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '$anomalyCount unusual pattern(s) found in your energy usage',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/insights');
              },
              child: const Text('View'),
            ),
          ],
        ),
      ),
    );
  }
}

// ML Insights Button Widget
class MLInsightsButton extends StatelessWidget {
  final VoidCallback onPressed;

  const MLInsightsButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.cyanAccent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        icon: const Icon(Icons.psychology, color: Colors.black),
        label: const Text(
          'View AI Insights',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
