# Energy Goal Tracking with Carry-Forward Feature

## Overview
The WattBuddy system now includes a comprehensive goal tracking feature that allows users to set daily and monthly energy consumption limits with intelligent carry-forward capability.

## Key Features

### 1. Goal Management
- **Daily Limit**: Set maximum kWh consumption per day
- **Monthly Limit**: Set maximum kWh consumption per month
- **Carry-Forward**: Unused daily allocation automatically carries to next day

### 2. Carry-Forward Logic
When enabled, the system:
- Calculates remaining energy at end of each day
- Carries forward unused allocation to next day
- Only carries forward if limit wasn't exceeded
- Automatically resets at midnight

**Example:**
```
Daily Limit: 5 kWh
Day 1 Usage: 3 kWh
Day 1 Remaining: 2 kWh

Day 2 Available: 5 kWh (base) + 2 kWh (carried) = 7 kWh total
```

### 3. Real-Time Alerts
The system monitors usage and sends alerts via Socket.io:
- **Warning Alert** (>80% usage): Early warning before exceeding limit
- **Exceeded Alert** (>100% usage): Notification when limit is exceeded
- **Progress Updates**: Real-time updates on current usage percentage

## Database Schema

### user_goals Table
```sql
CREATE TABLE user_goals (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL UNIQUE,
  daily_limit_kwh FLOAT DEFAULT 10.0,
  monthly_limit_kwh FLOAT DEFAULT 300.0,
  carry_forward_enabled BOOLEAN DEFAULT true,
  carried_over_kwh FLOAT DEFAULT 0,
  last_reset_date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

### goal_tracking Table
Stores historical tracking data for analytics:
```sql
CREATE TABLE goal_tracking (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  tracking_date DATE NOT NULL,
  daily_usage_kwh FLOAT DEFAULT 0,
  daily_limit_kwh FLOAT DEFAULT 0,
  carried_over_kwh FLOAT DEFAULT 0,
  total_available_kwh FLOAT DEFAULT 0,
  remaining_kwh FLOAT DEFAULT 0,
  exceeded BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, tracking_date)
);
```

## API Endpoints

### Set User Goals
```
POST /api/goals/set
```
**Body:**
```json
{
  "userId": 11,
  "dailyLimitKwh": 5.0,
  "monthlyLimitKwh": 150.0,
  "carryForwardEnabled": true
}
```

**Response:**
```json
{
  "success": true,
  "message": "Goals updated successfully",
  "goals": {
    "user_id": 11,
    "daily_limit_kwh": 5,
    "monthly_limit_kwh": 150,
    "carry_forward_enabled": true,
    "carried_over_kwh": 0
  }
}
```

### Get User Goals
```
GET /api/goals/:userId
```
**Response:**
```json
{
  "success": true,
  "goals": {
    "user_id": 11,
    "daily_limit_kwh": 5,
    "monthly_limit_kwh": 150,
    "carry_forward_enabled": true,
    "carried_over_kwh": 2.0,
    "last_reset_date": "2026-03-05"
  }
}
```

### Get Current Progress
```
GET /api/goals/progress/:userId
```
**Response:**
```json
{
  "success": true,
  "progress": {
    "date": "2026-03-05",
    "daily": {
      "currentUsage": 3.5,
      "dailyLimit": 5.0,
      "carriedOver": 2.0,
      "totalAvailable": 7.0,
      "remaining": 3.5,
      "percentageUsed": 50.0,
      "exceeded": false,
      "status": "good"
    },
    "monthly": {
      "currentUsage": 45.2,
      "monthlyLimit": 150.0,
      "remaining": 104.8,
      "percentageUsed": 30.13,
      "exceeded": false,
      "status": "good"
    },
    "carryForwardEnabled": true
  }
}
```

### Get Goal History
```
GET /api/goals/history/:userId?days=30
```
**Response:**
```json
{
  "success": true,
  "history": [
    {
      "tracking_date": "2026-03-04",
      "daily_usage_kwh": 3.0,
      "daily_limit_kwh": 5.0,
      "carried_over_kwh": 0,
      "total_available_kwh": 5.0,
      "remaining_kwh": 2.0,
      "exceeded": false
    }
  ],
  "count": 1
}
```

### Force Daily Reset (Testing)
```
POST /api/goals/reset/:userId
```

## Socket.io Events

### Goal Progress Update
Emitted after each data write:
```javascript
{
  event: 'goal_progress_update',
  data: {
    userId: "11",
    daily: { /* daily progress */ },
    monthly: { /* monthly progress */ },
    timestamp: "2026-03-05T10:30:00.000Z"
  }
}
```

### Goal Alerts
Emitted when thresholds are crossed:

**Daily Warning (>80%):**
```javascript
{
  event: 'goal_alert',
  data: {
    type: 'daily_warning',
    userId: "11",
    message: "⚠️ Approaching daily limit: 85% used (4.25 / 5.0 kWh)",
    progress: { /* daily stats */ },
    timestamp: "2026-03-05T10:30:00.000Z"
  }
}
```

**Daily Exceeded:**
```javascript
{
  event: 'goal_alert',
  data: {
    type: 'daily_exceeded',
    userId: "11",
    message: "⚠️ Daily limit exceeded! Used 5.50 kWh of 5.00 kWh available",
    progress: { /* daily stats */ },
    timestamp: "2026-03-05T10:30:00.000Z"
  }
}
```

## Service Methods

### GoalTrackingService

#### setUserGoals(userId, goals)
Sets or updates user's energy goals.

#### getUserGoals(userId)
Retrieves user's current goal settings.

#### checkAndResetDaily(userId)
Checks if daily reset is needed and performs carry-forward calculation.

#### getCurrentProgress(userId)
Gets current day's progress including daily and monthly stats.

#### getGoalHistory(userId, days)
Retrieves historical goal tracking data.

## Integration with ESP32 Data Flow

The goal tracking is automatically triggered when ESP32 sends data:

1. **Data Received** → ESP32 POST to `/api/esp32/data`
2. **Daily Usage Aggregated** → `DailyAnalyticsService.aggregateDailyUsage()`
3. **Daily Reset Check** → `GoalTrackingService.checkAndResetDaily()`
4. **Progress Calculated** → `GoalTrackingService.getCurrentProgress()`
5. **Alerts Sent** → Socket.io emits to Flutter app

## Testing

Run the test scripts:

```bash
# Test basic goal tracking
node test_goal_tracking.js

# Test carry-forward scenarios
node test_carry_forward.js
```

## Usage Examples

### Example 1: Basic Setup
```javascript
// Set 5 kWh daily limit, 150 kWh monthly limit
await GoalTrackingService.setUserGoals(11, {
  dailyLimitKwh: 5.0,
  monthlyLimitKwh: 150.0,
  carryForwardEnabled: true
});
```

### Example 2: Check Progress
```javascript
const progress = await GoalTrackingService.getCurrentProgress(11);
console.log(`Used ${progress.daily.percentageUsed}% of daily limit`);
```

### Example 3: Disable Carry-Forward
```javascript
await GoalTrackingService.setUserGoals(11, {
  carryForwardEnabled: false
});
```

## Carry-Forward Scenarios

### Scenario 1: Under Limit
```
Daily Limit: 5 kWh
Used: 3 kWh
Remaining: 2 kWh
→ Carries forward 2 kWh to next day
→ Next day available: 7 kWh (5 + 2)
```

### Scenario 2: Exceeded Limit
```
Daily Limit: 5 kWh
Used: 6 kWh
Remaining: -1 kWh
→ Carries forward 0 kWh (exceeded)
→ Next day available: 5 kWh (reset to base)
```

### Scenario 3: Carry-Forward Disabled
```
Daily Limit: 5 kWh
Used: 3 kWh
Carry-Forward: Disabled
→ Carries forward 0 kWh
→ Next day available: 5 kWh (always base limit)
```

## Status Indicators

- **good**: Usage ≤ 80% of limit (green)
- **warning**: Usage > 80% but ≤ 100% (yellow)
- **exceeded**: Usage > 100% (red)

## Future Enhancements

1. **Weekly Goals**: Add weekly limit tracking
2. **Custom Schedules**: Different limits for weekdays/weekends
3. **Smart Recommendations**: AI-suggested limits based on historical usage
4. **Notifications**: Email/SMS alerts for exceeded limits
5. **Family Sharing**: Share limits across multiple users
6. **Gamification**: Rewards for staying under limits

## Files Modified/Created

### Created Files:
- `services/goalTrackingService.js` - Core goal tracking logic
- `controllers/goalController.js` - API request handlers
- `routes/goalRoutes.js` - Route definitions
- `test_goal_tracking.js` - Basic functionality tests
- `test_carry_forward.js` - Carry-forward scenario tests

### Modified Files:
- `initDb.js` - Added user_goals and goal_tracking tables
- `server.js` - Integrated goal tracking with ESP32 data flow

## Support

For issues or questions, refer to the test files for usage examples or check the service method documentation.
