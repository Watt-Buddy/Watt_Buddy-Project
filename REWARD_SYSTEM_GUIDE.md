# ⭐ Energy Saver Reward System

## Overview
The WattBuddy reward system gamifies energy conservation by awarding **Energy Saver Points** for consistent consumption within goals. Users can unlock achievements, climb competitive tiers (Bronze → Silver → Gold → Platinum), and see their progress on a leaderboard.

## 🎯 Key Features

### 1. Points System
Users earn points daily based on:
- **Base Points** (10 pts): Staying under daily limit
- **Efficiency Bonuses**:
  - 50% Efficiency: +15 pts (using ≤50% of limit)
  - 30% Efficiency: +25 pts (using ≤30% of limit)
- **Streak Bonuses**:
  - 7+ day streak: +7 pts/day
  - 30+ day streak: +15 pts/day
  - 100+ day streak: +50 pts/day
- **Consistency Bonus** (10 pts): Predictable usage patterns
- **Achievement Bonuses**: 5-500 pts per achievement

### 2. Achievements System
8 achievable milestones:

| Achievement | Points | Condition |
|---|---|---|
| 🏁 First Day Under Limit | 5 | Stay under limit once |
| 🔥 50% Efficiency | 25 | Use ≤50% of daily limit |
| ⚡ 30% Efficiency | 75 | Use ≤30% of daily limit |
| 🔗 7-Day Streak | 50 | 7 consecutive days under limit |
| 🔗 30-Day Streak | 200 | 30 consecutive days under limit |
| 🔗 100-Day Streak | 500 | 100 consecutive days under limit |
| 💪 Power User | 50 | Maintain consistent usage |
| 💰 Energy Saver | 100 | Earn 100 points in a week |

### 3. Tier System
Progress through 4 ranks:

| Tier | Points Required | Badge | Description |
|---|---|---|---|
| 🥉 Bronze | 0 | Newcomer | Just started saving |
| 🥈 Silver | 100 | Energy Conscious | Good effort! |
| 🥇 Gold | 500 | Expert Saver | Outstanding discipline |
| 👑 Platinum | 1500 | Master Conservationist | Elite energy saver |

### 4. Streak Tracking
- **Current Streak**: Consecutive days under daily limit
- **Streak Bonuses**: Extra points for maintaining streaks
- **Lost on Exceeded**: Streak resets if limit exceeded

### 5. Leaderboard
- Compare with other users globally
- Real-time ranking updates
- Top 10 energy savers displayed

## 📊 Points Example

**Day with 2.5 kWh used (Daily Limit: 5 kWh)**
```
Daily Usage: 2.5 / 5 kWh = 50%

Points Breakdown:
  ✅ Under limit bonus: +10 pts
  ✅ 50% Efficiency: +15 pts
  ✅ 7-Day Streak bonus: +7 pts
  ✅ Consistency: +10 pts
  ────────────────────────
     Total: 42 points
```

## API Endpoints

### Get User Rewards Profile
```bash
GET /api/rewards/:userId
```
**Response:**
```json
{
  "success": true,
  "rewards": {
    "user_id": 11,
    "totalPoints": 160,
    "tier": "Silver",
    "currentStreak": 6,
    "achievementsUnlocked": 3,
    "achievements": [
      {
        "achievement_key": "efficiency_50",
        "name": "50% Efficiency",
        "points_reward": 25,
        "unlocked_at": "2026-02-28T10:30:00.000Z"
      }
    ],
    "progressToNextTier": {
      "nextTier": "Gold",
      "pointsNeeded": 340,
      "progressPercent": 15
    }
  }
}
```

### Get Points History
```bash
GET /api/rewards/history/:userId?days=30
```
**Response:**
```json
{
  "success": true,
  "history": [
    {
      "points_date": "2026-03-05",
      "points_earned": 42,
      "reason": "Under limit: +10 | 50% Efficiency: +15 | Streak: +7 | Consistency: +10"
    }
  ],
  "count": 30
}
```

### Get Leaderboard
```bash
GET /api/rewards/leaderboard?limit=10
```
**Response:**
```json
{
  "success": true,
  "leaderboard": [
    {
      "rank": 1,
      "user_id": 11,
      "username": "ramanan",
      "total_points": 420,
      "tier": "Silver",
      "current_streak": 15,
      "achievements_unlocked": 4
    }
  ],
  "count": 10
}
```

### Get All Achievements
```bash
GET /api/rewards/achievements
```
**Response:**
```json
{
  "success": true,
  "achievements": [
    {
      "achievement_key": "first_day_under",
      "name": "First Day Under Limit",
      "description": "Stay under daily limit for the first time",
      "points_reward": 5,
      "tier_requirement": "Bronze"
    }
  ],
  "count": 8
}
```

### Calculate Daily Points (Testing)
```bash
POST /api/rewards/calculate/:userId?date=2026-03-05
```

## Socket.io Events

### Reward Update
Emitted after points are calculated:
```javascript
{
  event: 'reward_update',
  data: {
    userId: "11",
    pointsEarned: 42,
    reasons: [
      "Under limit: +10 points",
      "50% Efficiency bonus: +15 points",
      "Streak bonus: +7 points",
      "Consistency bonus: +10 points"
    ],
    totalPoints: 160,
    tier: "Silver",
    currentStreak: 6,
    achievementsUnlocked: 3,
    progressToNextTier: {
      nextTier: "Gold",
      pointsNeeded: 340,
      progressPercent: 15
    },
    timestamp: "2026-03-05T11:30:00.000Z"
  }
}
```

### Achievement Unlocked
Emitted when achievement is unlocked:
```javascript
{
  event: 'achievement_unlocked',
  data: {
    userId: "11",
    achievement_key: "efficiency_50",
    name: "50% Efficiency",
    points_reward: 25,
    timestamp: "2026-03-05T11:30:00.000Z"
  }
}
```

## Database Tables

### user_rewards
Stores cumulative points and tier for each user.

### daily_points
Historical daily points for analytics.

### achievements
Master list of 8 achievements with descriptions.

### user_achievements
Tracks which achievements each user has unlocked.

## Integration with Goal Tracking

Points are **automatically calculated** when:
1. Daily usage is aggregated (`daily_usage` table)
2. Goal tracking is recorded (`goal_tracking` table)
3. ESP32 data triggers daily aggregation

The system works seamlessly with carry-forward logic:
- Extra points for efficient days
- Streaks reset on exceeded days
- No points if daily limit exceeded

## Testing

```bash
# Test reward system with simulated data
node test_reward_system.js
```

**Test Output Shows:**
- ✅ 8 achievements available
- ✅ Points calculated correctly per day
- ✅ Tier progression (Bronze → Silver → Gold)
- ✅ Streak tracking (consecutive under-limit days)
- ✅ Leaderboard ranking
- ✅ Progress to next tier

## 🎓 For Faculty Demonstration

**Innovation Highlights:**
1. **Gamification**: Makes conservation engaging (not just monitoring)
2. **Multi-Factor Rewards**: Streaks, efficiency, consistency
3. **Tier Progression**: Visible achievement progression
4. **Competitive Element**: Global leaderboard
5. **Automatic Calculation**: No user action needed

**Demo Flow:**
1. Show example user profile:
   ```bash
   curl http://192.168.184.49:4000/api/rewards/11
   ```
   Output: 160 points, Silver tier, 6-day streak

2. Show achievements:
   ```bash
   curl http://192.168.184.49:4000/api/rewards/achievements
   ```
   Display 8 available achievements

3. Show leaderboard:
   ```bash
   curl http://192.168.184.49:4000/api/rewards/leaderboard?limit=5
   ```
   Show top 5 energy savers

4. Show points history:
   ```bash
   curl http://192.168.184.49:4000/api/rewards/history/11?days=7
   ```
   Display daily points breakdown

5. Live demo: Turn on appliance, show Socket.io 'reward_update' event with points earned.

## Points Per Day Examples

**Best Case (30% efficiency, on streak, consistent):**
- Base: 10 pts
- 30% Efficiency: +25 pts
- 30-Day Streak: +15 pts
- Consistency: +10 pts
- **Total: 60 pts/day × 365 = 21,900 pts/year**

**Good Case (50% efficiency, 7-day streak):**
- Base: 10 pts
- 50% Efficiency: +15 pts
- 7-Day Streak: +7 pts
- **Total: 32 pts/day**

**Minimum Case (just under limit, no streak):**
- **Total: 10 pts/day**

**Exceeded (no points):**
- **Total: 0 pts/day**

## Tier Benefits (Future Enhancement)

Could add:
- 🥉 Bronze: Standard features
- 🥈 Silver: Unlock detailed analytics
- 🥇 Gold: Renewable energy rebates
- 👑 Platinum: Premium support, consultations

## Files Created/Modified

### New Files:
- `services/rewardSystemService.js` - Core reward logic
- `controllers/rewardController.js` - API handlers
- `routes/rewardRoutes.js` - Route definitions
- `test_reward_system.js` - Testing script

### Modified Files:
- `initDb.js` - Added reward tables
- `server.js` - Integrated reward calculation with ESP32 data flow

## Why This is Innovative

Traditional smart meters show **only consumption**. WattBuddy's reward system:
1. **Motivates** users to save (intrinsic engagement)
2. **Gamifies** conservation (fun, not punishment)
3. **Recognizes** consistency and streaks (behavioral psychology)
4. **Creates community** via leaderboards (social motivation)
5. **Combines with ML** (anomaly + rewards = complete system)

This makes WattBuddy not just a monitoring tool, but a **behavioral change platform** for energy conservation.
