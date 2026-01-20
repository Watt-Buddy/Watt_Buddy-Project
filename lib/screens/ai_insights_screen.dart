import 'package:flutter/material.dart';
import '../services/ml_service.dart';
import '../utils/responsive_scaffold.dart';

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
    return ResponsiveScaffold(
      currentRoute: '/insights',
      body: Scaffold(
        backgroundColor: const Color(0xFF0F0F23),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A3A),
          elevation: 0,
          title: const Text(
            'AI Energy Insights',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
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

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }

                  if (!snapshot.hasData || !(snapshot.data?['success'] ?? false)) {
                    return Center(
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'Unable to load insights',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => setState(() {
                              insightsFuture = MLService.getInsights(widget.userId);
                            }),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                            ),
                            child: const Text('Retry', style: TextStyle(color: Colors.black)),
                          ),
                        ],
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

                      const SizedBox(height: 24),

                      // ENERGY STATS SUMMARY
                      _buildEnergySummary(insights),
                    ],
                  );
                },
              ),
            ],
          ),
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
              'Severity Level: ${severity.toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (severity / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                severity > 75 ? Colors.redAccent : Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '⚠️ Monitor your energy consumption and consider reducing usage',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ] else
            const Text(
              '✓ Your energy consumption is within normal parameters',
              style: TextStyle(color: Colors.greenAccent, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildPatternCard(Map<String, dynamic> pattern) {
    final avgUsage = (pattern['average_usage'] ?? 0.0) as num;
    final peakUsage = (pattern['peak_usage'] ?? 0.0) as num;
    final minUsage = (pattern['min_usage'] ?? 0.0) as num;
    final stdDev = (pattern['std_dev'] ?? 0.0) as num;

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
            '${avgUsage.toStringAsFixed(2)} kW',
            Icons.flash_on,
          ),
          _patternMetric(
            'Peak Usage',
            '${peakUsage.toStringAsFixed(2)} kW',
            Icons.trending_up,
          ),
          _patternMetric(
            'Minimum Usage',
            '${minUsage.toStringAsFixed(2)} kW',
            Icons.trending_down,
          ),
          _patternMetric(
            'Variability',
            '${stdDev.toStringAsFixed(2)} σ',
            Icons.show_chart,
          ),
        ],
      ),
    );
  }

  Widget _patternMetric(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white54, size: 20),
                SizedBox(width: 12),
                Text(
                  'No suggestions at this time',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
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
    final priority = (suggestion['priority'] ?? 'medium').toString().toLowerCase();
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
              Expanded(
                child: Text(
                  suggestion['title'] ?? 'Suggestion',
                  style: TextStyle(
                    color: priorityColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
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
              Expanded(
                child: Text(
                  suggestion['action'] ?? '',
                  style: TextStyle(
                    color: priorityColor,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
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

  Widget _buildEnergySummary(Map<String, dynamic> insights) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purpleAccent.withValues(alpha: 0.2),
            Colors.blueAccent.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purpleAccent, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: Colors.purpleAccent, size: 24),
              SizedBox(width: 12),
              Text(
                'Energy Summary',
                style: TextStyle(
                  color: Colors.purpleAccent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _summaryItem('Daily Average', '${(insights['daily_avg'] ?? 0).toStringAsFixed(2)} kWh', Colors.cyanAccent),
              _summaryItem('Monthly Estimate', '₹${(insights['monthly_cost'] ?? 0).toStringAsFixed(0)}', Colors.yellowAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
