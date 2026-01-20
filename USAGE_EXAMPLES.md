# 📱 Monthly Usage Limit - Usage Examples & Scenarios

## 🎯 Scenario 1: Normal Month (No Excess)

```
Month: January 2026
Allocated: 300 kWh
Consumed: 250 kWh
Remaining: 50 kWh
Unused: 50 kWh × 50% = 25 kWh carryover

Status: ✅ ON TRACK

Next Month Allocation: 300 + 25 = 325 kWh
```

**Dashboard Display:**
```
Monthly Usage Limit
Status: On Track (83.3%)
████████░░░░░░░░░░

Consumed: 250.00 kWh | Remaining: 50.00 kWh | Limit: 300.00 kWh

💝 Carryover: 25.00 kWh from last month
```

---

## 🎯 Scenario 2: Approaching Limit (75%)

```
Month: February 2026
Allocated: 325 kWh (300 + 25 carryover)
Consumed: 245 kWh (75% of 325)
Remaining: 80 kWh
```

**Dashboard Display:**
```
Monthly Usage Limit
Status: Warning (75.4%)
███████████░░░░░░░

Consumed: 245.00 kWh | Remaining: 80.00 kWh | Limit: 325.00 kWh
```

**Notification Sent:**
```
⚠️ Usage Warning
You've used 75.4% of your monthly limit (245.00/325.00 kWh)
Review your appliances and adjust consumption to save energy
```

---

## 🎯 Scenario 3: Critical Level (90%)

```
Month: March 2026
Allocated: 300 kWh
Consumed: 270 kWh (90%)
Remaining: 30 kWh
```

**Dashboard Display:**
```
Monthly Usage Limit
Status: Critical (90%)
█████████░░░░░░░░░

Consumed: 270.00 kWh | Remaining: 30.00 kWh | Limit: 300.00 kWh
```

**Notification Sent:**
```
🚨 Critical Alert
You've used 90% of your monthly limit (270.00/300.00 kWh)
Reduce consumption immediately to avoid excess charges
```

---

## 🎯 Scenario 4: Limit Exceeded

```
Month: April 2026
Allocated: 300 kWh
Consumed: 330 kWh (110%)
Remaining: -30 kWh
Excess: 30 kWh
```

**Dashboard Display:**
```
Monthly Usage Limit
Status: Limit Exceeded! (110%)
█████████████░░░░░

Consumed: 330.00 kWh | Remaining: 30.00 kWh over | Limit: 300.00 kWh

⚠️ You have exceeded your monthly limit by 30.00 kWh
```

**Notifications Sent:**
```
At 100%:
🚨 Monthly Limit Exceeded!
You have exceeded your monthly energy limit!
Additional charges may apply for excess consumption.

Database Entries:
- usage_alert: alert_type='exceeded', threshold=100, excess_amount=30
- notification: type='usage_exceeded', severity='critical'
```

---

## 📊 API Usage Examples

### **Example 1: Initialize User with Custom Limit**

```bash
# Set custom monthly limit for user
curl -X POST http://localhost:4000/api/usage/monthly-limit \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user123",
    "limitKwh": 250
  }'

Response:
{
  "success": true,
  "data": {
    "id": 1,
    "user_id": "user123",
    "monthly_limit_kwh": 250,
    "created_at": "2026-01-06T12:00:00Z"
  }
}
```

### **Example 2: Daily Usage Updates**

```bash
# Report daily usage (simulating smart meter reading)
curl -X POST http://localhost:4000/api/usage/daily-usage \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user123",
    "dailyKwh": 8.5,
    "usageDate": "2026-01-06"
  }'

Response:
{
  "success": true,
  "message": "Daily usage updated",
  "data": {
    "user_id": "user123",
    "usage_date": "2026-01-06",
    "total_kwh": 8.5
  }
}
```

### **Example 3: Get Monthly Summary**

```bash
curl http://localhost:4000/api/usage/monthly-summary/user123

Response:
{
  "success": true,
  "summary": {
    "month": "2026-01",
    "allocated": 250,
    "consumed": 145.5,
    "remaining": 104.5,
    "carryoverFromPrevious": 0,
    "carryoverToNext": 0,
    "exceeded": false,
    "excessAmount": 0,
    "usagePercentage": 58.2,
    "recentAlerts": [
      {
        "id": 1,
        "alert_type": "approaching",
        "threshold_percentage": 50,
        "current_usage": 125,
        "monthly_limit": 250,
        "message": "You've used 50% of your monthly limit",
        "is_resolved": false,
        "created_at": "2026-01-15T10:30:00Z"
      }
    ]
  }
}
```

### **Example 4: Get Usage Forecast**

```bash
curl http://localhost:4000/api/usage/forecast/user123

Response:
{
  "success": true,
  "forecast": {
    "averageDailyUsage": "8.3",
    "remainingDaysInMonth": 25,
    "currentConsumption": "145.5",
    "monthlyLimit": "250",
    "projectedUsage": "352.2",
    "projectedRemaining": "-102.2",
    "willExceed": true,
    "projectedExcess": "102.2"
  }
}
```

---

## 📱 Flutter Widget Integration Examples

### **Example 1: Basic Dashboard Integration**

```dart
// dashboard_screen.dart

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String userId = 'user123';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Energy Dashboard',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),

            // Monthly Limit Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MonthlyLimitCard(
                userId: userId,
                onLimitExceeded: () {
                  _showLimitExceededNotification();
                },
              ),
            ),

            // Other dashboard widgets...
          ],
        ),
      ),
    );
  }

  void _showLimitExceededNotification() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.warning_rounded, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text('⚠️ Monthly limit exceeded!'),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
```

### **Example 2: Custom Limit Dialog**

```dart
void _showSetLimitDialog(String userId) {
  final limitController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Set Monthly Limit'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter your monthly energy limit (in kWh):'),
          const SizedBox(height: 16),
          TextField(
            controller: limitController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '300',
              suffixText: 'kWh',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final limit = double.tryParse(limitController.text);
            if (limit != null && limit > 0) {
              final success = await MonthlyUsageService.setMonthlyLimit(
                userId: userId,
                limitKwh: limit,
              );

              if (mounted) {
                Navigator.pop(context);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Limit set to ${limit.toStringAsFixed(2)} kWh'),
                      backgroundColor: Colors.greenAccent,
                    ),
                  );
                }
              }
            }
          },
          child: const Text('Set'),
        ),
      ],
    ),
  );
}
```

### **Example 3: Usage Forecast Display**

```dart
class UsageForecastWidget extends StatelessWidget {
  final String userId;

  const UsageForecastWidget({required this.userId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: MonthlyUsageService.getUsageForecast(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !(snapshot.data?['success'] ?? false)) {
          return const SizedBox.shrink();
        }

        final forecast = snapshot.data?['forecast'] ?? {};
        final willExceed = forecast['willExceed'] ?? false;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: willExceed
                ? Colors.redAccent.withOpacity(0.1)
                : Colors.greenAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: willExceed ? Colors.redAccent : Colors.greenAccent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    willExceed ? Icons.trending_up : Icons.trending_down,
                    color: willExceed ? Colors.redAccent : Colors.greenAccent,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    willExceed ? 'Projected to Exceed' : 'Projected to Be On Track',
                    style: TextStyle(
                      color: willExceed ? Colors.redAccent : Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Average daily: ${forecast['averageDailyUsage']} kWh',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Remaining days: ${forecast['remainingDaysInMonth']}',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Projected end-of-month: ${forecast['projectedUsage']} kWh',
                style: const TextStyle(color: Colors.white70),
              ),
              if (willExceed)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Projected excess: ${forecast['projectedExcess']} kWh',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
```

---

## 📊 Database Query Examples

### **Get All Users Approaching Limit**

```sql
SELECT DISTINCT u.id, u.username, mu.consumed_kwh, mu.allocated_kwh,
       (mu.consumed_kwh / mu.allocated_kwh * 100) as usage_percentage
FROM users u
JOIN monthly_usage mu ON u.id = mu.user_id
WHERE month_year = DATE_TRUNC('month', CURRENT_DATE)::text
  AND (mu.consumed_kwh / mu.allocated_kwh) >= 0.75
ORDER BY usage_percentage DESC;
```

### **Get Carryover Stats**

```sql
SELECT u.username, 
       SUM(mu.carryover_from_previous) as total_carryover_received,
       SUM(mu.carryover_to_next) as total_carryover_preserved
FROM users u
JOIN monthly_usage mu ON u.id = mu.user_id
GROUP BY u.id, u.username
ORDER BY total_carryover_received DESC;
```

### **Find Users Exceeding Limits**

```sql
SELECT u.username, mu.month_year, mu.consumed_kwh, mu.allocated_kwh,
       mu.excess_amount, COUNT(ua.id) as alert_count
FROM users u
JOIN monthly_usage mu ON u.id = mu.user_id
LEFT JOIN usage_alerts ua ON u.id = ua.user_id 
  AND DATE_TRUNC('month', ua.created_at)::text = mu.month_year
WHERE mu.exceeded = true
GROUP BY u.id, u.username, mu.month_year, mu.consumed_kwh, 
         mu.allocated_kwh, mu.excess_amount
ORDER BY mu.excess_amount DESC;
```

---

## 🎊 Summary

With these implementations, your WattBuddy app now has:

✅ **Monthly Usage Limits** - User-defined consumption caps  
✅ **Automatic Tracking** - Real-time consumption monitoring  
✅ **Smart Carryover** - 50% of unused units preserved for next month  
✅ **Multi-Tier Alerts** - Notifications at 50%, 75%, 90%, 100%  
✅ **Usage Forecast** - Predicts end-of-month consumption  
✅ **Beautiful UI** - Color-coded limit display on dashboard  
✅ **Comprehensive Logging** - Full alert and usage history  

**Everything is ready to deploy!** 🚀
