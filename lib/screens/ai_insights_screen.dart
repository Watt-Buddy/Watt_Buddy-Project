import 'package:flutter/material.dart';
import '../services/ml_service.dart';

class AIInsightsScreen extends StatefulWidget {
  final String userId;

  const AIInsightsScreen({super.key, required this.userId});

  @override
  State<AIInsightsScreen> createState() => _AIInsightsScreenState();
}

class _AIInsightsScreenState extends State<AIInsightsScreen> {
  late Future<Map<String, dynamic>> insightsFuture;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    insightsFuture = MLService.getInsights(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A3A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI Energy Insights',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            const Text(
              'AI Energy Insights',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Personalized recommendations powered by machine learning',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 30),

            // INSIGHTS CONTENT
            FutureBuilder<Map<String, dynamic>>(
              future: insightsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.cyanAccent,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || !(snapshot.data?['success'] ?? false)) {
                  return const Center(
                    child: Text(
                      'Failed to load insights',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                final insights = snapshot.data?['insights'];
                final anomalies = insights?['anomalies'];
                final pattern = insights?['pattern'];
                final suggestions = insights?['suggestions'] as List? ?? [];

                return Column(
                  children: [
                    // ANOMALY ALERT
                    if (anomalies != null)
                      _buildAnomalyCard(anomalies),

                    const SizedBox(height: 24),

                    // USAGE PATTERN
                    if (pattern != null)
                      _buildPatternCard(pattern),

                    const SizedBox(height: 24),

                    // SUGGESTIONS
                    _buildSuggestionsSection(suggestions),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnomalyCard(Map<String, dynamic> anomalies) {
    final isAnomaly = anomalies['is_anomaly'] ?? false;
    final severity = anomalies['severity'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isAnomaly
            ? Colors.redAccent.withValues(alpha: 0.1)
            : Colors.greenAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAnomaly ? Colors.redAccent : Colors.greenAccent,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAnomaly ? Icons.warning_rounded : Icons.check_circle_rounded,
                color: isAnomaly ? Colors.redAccent : Colors.greenAccent,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                isAnomaly ? 'Anomaly Detected' : 'Normal Usage Pattern',
                style: TextStyle(
                  color: isAnomaly ? Colors.redAccent : Colors.greenAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isAnomaly) ...[
            Text(
              'Severity Level: $severity%',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: severity / 100,
              minHeight: 6,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                severity > 75 ? Colors.redAccent : Colors.orangeAccent,
              ),
            ),
          ] else
            const Text(
              'Your energy consumption is within normal parameters',
              style: TextStyle(color: Colors.greenAccent, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildPatternCard(Map<String, dynamic> pattern) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_rounded, color: Colors.cyanAccent, size: 24),
              SizedBox(width: 12),
              Text(
                'Your Energy Pattern',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _patternMetric(
            'Average Usage',
            '${pattern['average_usage']?.toStringAsFixed(2) ?? '0.00'} kW',
            Icons.flash_on,
          ),
          _patternMetric(
            'Peak Usage',
            '${pattern['peak_usage']?.toStringAsFixed(2) ?? '0.00'} kW',
            Icons.trending_up,
          ),
          _patternMetric(
            'Minimum Usage',
            '${pattern['min_usage']?.toStringAsFixed(2) ?? '0.00'} kW',
            Icons.trending_down,
          ),
          _patternMetric(
            'Variability',
            '${pattern['std_dev']?.toStringAsFixed(2) ?? '0.00'} σ',
            Icons.show_chart,
          ),
        ],
      ),
    );
  }

  Widget _patternMetric(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsSection(List<dynamic> suggestions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.lightbulb_rounded, color: Colors.yellowAccent, size: 24),
            SizedBox(width: 12),
            Text(
              'Smart Suggestions',
              style: TextStyle(
                color: Colors.yellowAccent,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (suggestions.isEmpty)
          const Text(
            'No suggestions at this time',
            style: TextStyle(color: Colors.white70),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index] as Map<String, dynamic>;
              return _buildSuggestionCard(suggestion);
            },
          ),
      ],
    );
  }

  Widget _buildSuggestionCard(Map<String, dynamic> suggestion) {
    final priority = suggestion['priority'] ?? 'medium';
    final priorityColor = _getPriorityColor(priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: priorityColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: priorityColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: priorityColor.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                suggestion['title'] ?? 'Suggestion',
                style: TextStyle(
                  color: priorityColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  priority.toUpperCase(),
                  style: TextStyle(
                    color: priorityColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion['message'] ?? '',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: priorityColor, size: 18),
              const SizedBox(width: 8),
              Text(
                suggestion['action'] ?? '',
                style: TextStyle(
                  color: priorityColor,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          if (suggestion['savings_potential'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.savings, color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Potential savings: ₹${suggestion['savings_potential']}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'critical':
        return Colors.redAccent;
      case 'high':
        return Colors.orangeAccent;
      case 'medium':
        return Colors.yellowAccent;
      default:
        return Colors.cyanAccent;
    }
  }
}
