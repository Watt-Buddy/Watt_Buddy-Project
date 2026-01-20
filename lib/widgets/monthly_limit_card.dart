import 'package:flutter/material.dart';
import '../services/monthly_usage_service.dart';

class MonthlyLimitCard extends StatefulWidget {
  final String userId;
  final VoidCallback? onLimitExceeded;

  const MonthlyLimitCard({
    super.key,
    required this.userId,
    this.onLimitExceeded,
  });

  @override
  State<MonthlyLimitCard> createState() => _MonthlyLimitCardState();
}

class _MonthlyLimitCardState extends State<MonthlyLimitCard> {
  late Future<Map<String, dynamic>> summaryFuture;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    summaryFuture = MonthlyUsageService.getMonthlyUsageSummary(
      userId: widget.userId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: summaryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }

        if (!snapshot.hasData || !(snapshot.data?['success'] ?? false)) {
          return _buildErrorCard();
        }

        final summary = snapshot.data?['summary'];
        if (summary == null) {
          return _buildErrorCard();
        }

        final allocated = (summary['allocated'] ?? 300).toDouble();
        final consumed = (summary['consumed'] ?? 0).toDouble();
        final remaining = (summary['remaining'] ?? allocated).toDouble();
        final exceeded = summary['exceeded'] ?? false;
        final usagePercentage = (consumed / allocated) * 100;

        // Notify if exceeded
        if (exceeded && widget.onLimitExceeded != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onLimitExceeded!();
          });
        }

        return _buildLimitCard(
          allocated,
          consumed,
          remaining,
          exceeded,
          usagePercentage,
          summary,
        );
      },
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.flash_on_rounded, color: Colors.cyanAccent, size: 24),
              SizedBox(width: 12),
              Text(
                'Monthly Usage Limit',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent, width: 1),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on_rounded, color: Colors.cyanAccent, size: 24),
              SizedBox(width: 12),
              Text(
                'Monthly Usage Limit',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Text(
            'Unable to load usage data',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitCard(
    double allocated,
    double consumed,
    double remaining,
    bool exceeded,
    double usagePercentage,
    Map<String, dynamic> summary,
  ) {
    Color statusColor = Colors.greenAccent;
    String statusText = 'On Track';

    if (usagePercentage >= 100) {
      statusColor = Colors.redAccent;
      statusText = 'Limit Exceeded!';
    } else if (usagePercentage >= 90) {
      statusColor = Colors.orangeAccent;
      statusText = 'Critical';
    } else if (usagePercentage >= 75) {
      statusColor = Colors.yellowAccent;
      statusText = 'Warning';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.flash_on_rounded, color: Colors.cyanAccent, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Monthly Usage Limit',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Usage progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current Usage',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    '${usagePercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (consumed / allocated).clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Usage details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildUsageMetric(
                label: 'Consumed',
                value: '${consumed.toStringAsFixed(2)} kWh',
                color: Colors.cyanAccent,
              ),
              _buildUsageMetric(
                label: 'Remaining',
                value: exceeded
                    ? '${(summary['excess_amount'] as num).toStringAsFixed(2)} kWh over'
                    : '${remaining.toStringAsFixed(2)} kWh',
                color: exceeded ? Colors.redAccent : Colors.greenAccent,
              ),
              _buildUsageMetric(
                label: 'Limit',
                value: '${allocated.toStringAsFixed(2)} kWh',
                color: Colors.yellowAccent,
              ),
            ],
          ),

          // Carryover info if applicable
          if ((summary['carryover_from_previous'] ?? 0) > 0)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard, color: Colors.greenAccent, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Carryover: ${(summary['carryover_from_previous'] as num).toStringAsFixed(2)} kWh from last month',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Exceeded warning
          if (exceeded)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You have exceeded your monthly limit by ${(summary['excess_amount'] as num).toStringAsFixed(2)} kWh',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUsageMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
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
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
