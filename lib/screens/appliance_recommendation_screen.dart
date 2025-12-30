import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/responsive_scaffold.dart';

class ApplianceRecommendationScreen extends StatefulWidget {
  const ApplianceRecommendationScreen({super.key});

  @override
  State<ApplianceRecommendationScreen> createState() =>
      _ApplianceRecommendationScreenState();
}

class _ApplianceRecommendationScreenState
    extends State<ApplianceRecommendationScreen> {
  // Filters
  int selectedApplianceType = 0; // 0=All, 1=AC, 2=Fridge, 3=Fan, 4=Heater
  List<String> applianceTypes = ['All', 'AC', 'Fridge', 'Fan', 'Heater', 'Washing Machine'];
  
  double houseSize = 1200; // sq ft
  double monthlyUsage = 150; // kWh
  int usagePattern = 1; // 0=Rare, 1=Moderate, 2=Heavy
  double budgetRange = 5000; // rupees
  
  List<String> usagePatterns = ['Rare', 'Moderate', 'Heavy'];

  // Recommendations
  List<Map<String, dynamic>> recommendations = [];
  bool isLoading = false;
  double userCurrentConsumption = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Try to load from stored user data
    final storedUser = prefs.getString('wattBuddyUser');
    if (storedUser != null) {
      // User data available - can be used for personalization if needed
      // final user = jsonDecode(storedUser);
    }

    // Generate recommendations based on current filters
    _generateRecommendations();
  }

  void _generateRecommendations() {
    setState(() => isLoading = true);

    // Simulated recommendations based on filters
    final allRecommendations = [
      {
        'name': 'LG 5-Star Inverter AC',
        'type': 'AC',
        'power': 1200,
        'estimatedMonthlyCost': 3600,
        'savingsPotential': 1000,
        'rating': 4.8,
        'reviews': 2345,
        'price': 37500,
        'icon': Icons.ac_unit,
        'color': Color(0xFF00D4FF),
        'description': 'Energy efficient cooling solution for large rooms',
        'goodFor': ['High consumption areas', 'Summer relief', 'Comfort']
      },
      {
        'name': 'Samsung 5-Star Refrigerator',
        'type': 'Fridge',
        'power': 600,
        'estimatedMonthlyCost': 2100,
        'savingsPotential': 650,
        'rating': 4.6,
        'reviews': 1890,
        'price': 31500,
        'icon': Icons.kitchen,
        'color': Color(0xFF4ECDC4),
        'description': 'Large capacity with smart cooling technology',
        'goodFor': ['Food preservation', '24/7 operation', 'Savings']
      },
      {
        'name': 'Philips High-Speed Pedestal Fan',
        'type': 'Fan',
        'power': 75,
        'estimatedMonthlyCost': 250,
        'savingsPotential': 1250,
        'rating': 4.4,
        'reviews': 5670,
        'price': 3750,
        'icon': Icons.toys,
        'color': Color(0xFFFF6B6B),
        'description': 'Efficient air circulation for all seasons',
        'goodFor': ['Budget friendly', 'Low consumption', 'Effective cooling']
      },
      {
        'name': 'Daikin Inverter Heater',
        'type': 'Heater',
        'power': 2000,
        'estimatedMonthlyCost': 2900,
        'savingsPotential': 1650,
        'rating': 4.7,
        'reviews': 1234,
        'price': 26600,
        'icon': Icons.local_fire_department,
        'color': Color(0xFFFFB03B),
        'description': 'Intelligent heating for winter comfort',
        'goodFor': ['Cold climate', 'Quick heating', 'Thermostat control']
      },
      {
        'name': 'IFB Fully Automatic Washing Machine',
        'type': 'Washing Machine',
        'power': 2000,
        'estimatedMonthlyCost': 3300,
        'savingsPotential': 1500,
        'rating': 4.5,
        'reviews': 3456,
        'price': 43300,
        'icon': Icons.local_laundry_service,
        'color': Color(0xFF9D84B7),
        'description': 'Water and energy efficient cleaning',
        'goodFor': ['Large families', 'Daily laundry', 'Water saving']
      },
      {
        'name': 'Bajaj Mixing Star 500W Mixer',
        'type': 'Mixer',
        'power': 500,
        'estimatedMonthlyCost': 650,
        'savingsPotential': 400,
        'rating': 4.3,
        'reviews': 4567,
        'price': 5400,
        'icon': Icons.blender,
        'color': Color(0xFF6BCB77),
        'description': 'Powerful mixing for kitchen needs',
        'goodFor': ['Daily cooking', 'Meal prep', 'Kitchen efficiency']
      },
    ];

    // Filter recommendations
    List<Map<String, dynamic>> filtered = allRecommendations;

    if (selectedApplianceType != 0) {
      filtered = filtered
          .where((r) => r['type'] == applianceTypes[selectedApplianceType])
          .toList();
    }

    // Filter by house size suitability
    if (houseSize < 800) {
      filtered = filtered
          .where((r) =>
              (r['type'] == 'Fan' ||
               r['type'] == 'Heater' ||
               r['type'] == 'Mixer'))
          .toList();
    }

    // Filter by budget
    filtered =
        filtered.where((r) => (r['price'] as int) <= budgetRange).toList();

    // Sort by savings potential
    filtered.sort((a, b) => b['savingsPotential'].compareTo(a['savingsPotential']));

    setState(() {
      recommendations = filtered;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: 'Recommendations',
      body: Container(
        color: Color(0xFF0A0A2A),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                "Find the Right Appliance for You",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                "Personalized recommendations based on your consumption",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 30),

              // Filter Container
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Color(0xFF1A1A3A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Color(0xFF00D4FF), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Appliance Type Filter
                    Text(
                      "Appliance Type",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(
                          applianceTypes.length,
                          (index) => Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () {
                                setState(
                                    () => selectedApplianceType = index);
                                _generateRecommendations();
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selectedApplianceType == index
                                      ? Color(0xFF00D4FF)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selectedApplianceType == index
                                        ? Color(0xFF00D4FF)
                                        : Colors.grey.withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  applianceTypes[index],
                                  style: TextStyle(
                                    color: selectedApplianceType == index
                                        ? Colors.black
                                        : Colors.white70,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    // House Size Slider
                    Text(
                      "House Size",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          "500 sq ft",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: houseSize,
                            min: 500,
                            max: 5000,
                            activeColor: Color(0xFF00D4FF),
                            inactiveColor: Colors.grey.withOpacity(0.2),
                            onChanged: (value) {
                              setState(() => houseSize = value);
                              _generateRecommendations();
                            },
                          ),
                        ),
                        Text(
                          "5000 sq ft",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      "${houseSize.toStringAsFixed(0)} sq ft",
                      style: TextStyle(
                        color: Color(0xFF00D4FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),

                    // Monthly Usage Slider
                    Text(
                      "Average Monthly Units (kWh)",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          "50 kWh",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: monthlyUsage,
                            min: 50,
                            max: 500,
                            activeColor: Color(0xFF00D4FF),
                            inactiveColor: Colors.grey.withOpacity(0.2),
                            onChanged: (value) {
                              setState(() => monthlyUsage = value);
                              _generateRecommendations();
                            },
                          ),
                        ),
                        Text(
                          "500 kWh",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      "${monthlyUsage.toStringAsFixed(0)} kWh",
                      style: TextStyle(
                        color: Color(0xFF00D4FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20),

                    // Usage Pattern
                    Text(
                      "Usage Pattern",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 10),
                    Row(
                      children: List.generate(
                        usagePatterns.length,
                        (index) => Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => usagePattern = index);
                              _generateRecommendations();
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              margin: EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: usagePattern == index
                                    ? Color(0xFF00D4FF)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: usagePattern == index
                                      ? Color(0xFF00D4FF)
                                      : Colors.grey.withOpacity(0.3),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  usagePatterns[index],
                                  style: TextStyle(
                                    color: usagePattern == index
                                        ? Colors.black
                                        : Colors.white70,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    // Budget Range Slider
                    Text(
                      "Budget Range",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          "₹500",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Expanded(
                          child: Slider(
                            value: budgetRange,
                            min: 500,
                            max: 250000,
                            activeColor: Color(0xFF00D4FF),
                            inactiveColor: Colors.grey.withOpacity(0.2),
                            onChanged: (value) {
                              setState(() => budgetRange = value);
                              _generateRecommendations();
                            },
                          ),
                        ),
                        Text(
                          "₹2,50,000+",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      "₹${budgetRange.toStringAsFixed(0)}",
                      style: TextStyle(
                        color: Color(0xFF00D4FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 30),

              // Recommendations Section
              Text(
                "Recommended Appliances (${recommendations.length})",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),

              if (isLoading)
                Center(
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFF00D4FF)),
                  ),
                )
              else if (recommendations.isEmpty)
                Container(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.devices_other,
                            color: Colors.grey, size: 48),
                        SizedBox(height: 12),
                        Text(
                          "No appliances match your criteria",
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Column(
                  children: recommendations.map((appliance) {
                    return _buildApplianceCard(appliance);
                  }).toList(),
                ),

              SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApplianceCard(Map<String, dynamic> appliance) {
    final color = appliance['color'] as Color;
    // Calculate savings percentage if needed
    // final savingsPercent = ((appliance['savingsPotential'] as int) / (appliance['estimatedMonthlyCost'] as int) * 100).toStringAsFixed(0);

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF1A1A3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(appliance['icon'] as IconData,
                    color: color, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appliance['name'],
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      appliance['description'],
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "₹${(appliance['price'] as int).toString()}",
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 14),
                      SizedBox(width: 4),
                      Text(
                        "${appliance['rating']} (${appliance['reviews']})",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: 12),
          Divider(color: Colors.white.withOpacity(0.1)),
          SizedBox(height: 12),

          // Stats Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat(
                "Power",
                "${appliance['power']}W",
                Icons.bolt,
                color,
              ),
              _buildStat(
                "Monthly Cost",
                "₹${appliance['estimatedMonthlyCost']}",
                Icons.attach_money,
                color,
              ),
              _buildStat(
                "Potential Savings",
                "₹${appliance['savingsPotential']}",
                Icons.trending_down,
                Colors.green,
              ),
            ],
          ),

          SizedBox(height: 12),

          // Good For Tags
          Text(
            "Good for:",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: (appliance['goodFor'] as List<String>).map((tag) {
              return Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                  ),
                ),
              );
            }).toList(),
          ),

          SizedBox(height: 12),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _showApplianceDetails(appliance),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                padding: EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                "View Details",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 16),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  void _showApplianceDetails(Map<String, dynamic> appliance) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Color(0xFF1A1A3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          padding: EdgeInsets.all(20),
          constraints: BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    appliance['name'],
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                appliance['description'],
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 20),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (appliance['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (appliance['color'] as Color).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      "Price",
                      "₹${appliance['price']}",
                      appliance['color'],
                    ),
                    _buildDetailRow(
                      "Power Rating",
                      "${appliance['power']}W",
                      appliance['color'],
                    ),
                    _buildDetailRow(
                      "Monthly Operating Cost",
                      "₹${appliance['estimatedMonthlyCost']}",
                      appliance['color'],
                    ),
                    _buildDetailRow(
                      "Potential Monthly Savings",
                      "₹${appliance['savingsPotential']}",
                      Colors.green,
                    ),
                    _buildDetailRow(
                      "Rating",
                      "${appliance['rating']} ⭐ (${appliance['reviews']} reviews)",
                      appliance['color'],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appliance['color'] as Color,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    "Check Availability",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
