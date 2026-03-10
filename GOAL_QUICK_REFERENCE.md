# ⚡ Goal Tracking & Carry-Forward - Quick Reference

## 🎯 API Endpoints

### Set Goals
```bash
curl -X POST http://localhost:4000/api/goals/set \
  -H "Content-Type: application/json" \
  -d '{"userId":11, "dailyLimitKwh":5.0, "monthlyLimitKwh":150.0, "carryForwardEnabled":true}'
```

### Get Goals
```bash
curl http://localhost:4000/api/goals/11
```

### Get Progress
```bash
curl http://localhost:4000/api/goals/progress/11
```

### Get History
```bash
curl http://localhost:4000/api/goals/history/11?days=7
```

### Force Reset (Testing)
```bash
curl -X POST http://localhost:4000/api/goals/reset/11
```

## 📊 Key Features

| Feature | Description |
|---------|-------------|
| **Daily Limit** | Maximum kWh per day |
| **Monthly Limit** | Maximum kWh per month |
| **Carry-Forward** | Unused daily energy rolls over |
| **Auto Reset** | Midnight automatic reset with carry-over |
| **Real-Time Alerts** | Socket.io notifications at 80% & 100% |
| **History Tracking** | View past usage vs limits |

## 🔄 Carry-Forward Examples

| Scenario | Daily Limit | Used | Carried Over | Next Day Available |
|----------|-------------|------|--------------|-------------------|
| Under limit | 5 kWh | 3 kWh | 2 kWh | 7 kWh (5+2) |
| Exceeded | 5 kWh | 6 kWh | 0 kWh | 5 kWh (reset) |
| Disabled | 5 kWh | 3 kWh | 0 kWh | 5 kWh (no carry) |

## 🚨 Socket.io Events

### Listen for Progress Updates
```javascript
socket.on('goal_progress_update', (data) => {
  console.log(`Daily: ${data.daily.percentageUsed}%`);
  console.log(`Monthly: ${data.monthly.percentageUsed}%`);
});
```

### Listen for Alerts
```javascript
socket.on('goal_alert', (alert) => {
  // Types: 'daily_warning', 'daily_exceeded', 
  //        'monthly_warning', 'monthly_exceeded'
  console.log(alert.message);
});
```

## 🧪 Testing

```bash
# Test basic functionality
node test_goal_tracking.js

# Test carry-forward scenarios
node test_carry_forward.js
```

## 📝 Status Types

- **good** - Usage ≤ 80% (🟢)
- **warning** - 80% < Usage ≤ 100% (🟡)
- **exceeded** - Usage > 100% (🔴)

## 🗃️ Database Tables

### user_goals
Stores user's goal settings and current carry-over amount.

### goal_tracking
Historical daily records for analytics and charts.

## 🎓 For Faculty Demo

**Key Points to Highlight:**
1. User sets daily limit (e.g., 5 kWh)
2. System tracks real-time usage
3. Unused energy carries to next day automatically
4. Real-time alerts when approaching/exceeding limits
5. Historical tracking shows patterns over time
6. Works with existing Random Forest anomaly detection

**Demo Flow:**
1. Set goals: `POST /api/goals/set`
2. Check progress: `GET /api/goals/progress/11`
3. Show carry-forward: Run test script
4. Display real-time alerts in app
5. Show history: `GET /api/goals/history/11`
