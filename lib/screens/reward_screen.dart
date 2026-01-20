import 'package:flutter/material.dart';
import '../utils/responsive_scaffold.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  int totalPoints = 1250;
  int availablePoints = 850;
  int redeemedPoints = 400;

  final List<Map<String, dynamic>> rewards = [
    {
      'title': '₹100 Electricity Bill Voucher',
      'points': 500,
      'desc': 'Get ₹100 off on your electricity bill',
      'icon': Icons.bolt,
      'color': Colors.blue,
      'redeemed': false,
    },
    {
      'title': 'LED Bulb Discount',
      'points': 300,
      'desc': '15% off on energy efficient LED bulbs',
      'icon': Icons.lightbulb,
      'color': Colors.amber,
      'redeemed': true,
    },
    {
      'title': 'Free Energy Audit',
      'points': 800,
      'desc': 'Professional home energy audit',
      'icon': Icons.assessment,
      'color': Colors.green,
      'redeemed': false,
    },
  ];

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/rewards',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            const Text(
              "Rewards & Points",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Earn points by saving energy and redeem exciting rewards",
              style: TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 30),

            // POINTS SUMMARY
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
                      ? 3.0
                      : 3.8,
                  children: [
                    _summaryCard("Total Points", "$totalPoints"),
                    _summaryCard("Available", "$availablePoints"),
                    _summaryCard("Redeemed", "$redeemedPoints"),
                  ],
                );
              },
            ),

            const SizedBox(height: 30),

            // AVAILABLE REWARDS
            const Text(
              "Available Rewards",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),

            LayoutBuilder(
              builder: (context, c) {
                int cols = 3;
                if (c.maxWidth < 1000) cols = 2;
                if (c.maxWidth < 600) cols = 1;

                return GridView.builder(
                  itemCount: rewards.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.2,
                  ),
                  itemBuilder: (context, i) => _rewardCard(rewards[i]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- WIDGETS ----------------

  Widget _summaryCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rewardCard(Map<String, dynamic> reward) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(reward['icon'], color: reward['color'], size: 32),
          const SizedBox(height: 15),
          Text(
            reward['title'],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reward['desc'],
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${reward['points']} pts",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton(
                onPressed: reward['redeemed'] ? null : () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: reward['redeemed']
                      ? const Color.fromARGB(255, 236, 234, 234)
                      : const Color.fromARGB(255, 236, 238, 241),
                ),
                child: Text(reward['redeemed'] ? "Redeemed" : "Redeem"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
