# 🏆 Energy Saver Rewards - Quick Reference

## 📊 Points Earned by Scenario

| Scenario | Usage | Points | Reason |
|---|---|---|---|
| Excellent | 1.5 kWh (30%) | 35-60 pts | Efficiency + streak bonus |
| Good | 2.5 kWh (50%) | 25-42 pts | Base + efficiency |
| Average | 4.0 kWh (80%) | 10 pts | Base only |
| Exceeded | 6.0 kWh (120%) | 0 pts | Over limit |

## 🎯 Achievements

```
🏁 First Day Under Limit (5 pts)
🔥 50% Efficiency (25 pts) 
⚡ 30% Efficiency (75 pts)
🔗 7-Day Streak (50 pts)
🔗 30-Day Streak (200 pts)
🔗 100-Day Streak (500 pts)
💪 Power User (50 pts)
💰 Energy Saver (100 pts)
```

## 🥇 Tier Progression

**Bronze** 🥉 (0 pts) → **Silver** 🥈 (100 pts) → **Gold** 🥇 (500 pts) → **Platinum** 👑 (1500 pts)

## 🔥 Streak System

- Consecutive days under daily limit = streak
- Earn bonus points per day
- Resets if limit exceeded

| Streak Length | Bonus/Day |
|---|---|
| 7+ days | +7 pts |
| 30+ days | +15 pts |
| 100+ days | +50 pts |

## 📈 API Quick Commands

### Get Rewards
```bash
curl http://localhost:4000/api/rewards/11
```

### Get Points History (Last 7 days)
```bash
curl http://localhost:4000/api/rewards/history/11?days=7
```

### Get Leaderboard (Top 10)
```bash
curl http://localhost:4000/api/rewards/leaderboard?limit=10
```

### Get Achievements
```bash
curl http://localhost:4000/api/rewards/achievements
```

## 🎮 How It Works

1. **Daily Usage** → Aggregated at midnight
2. **Goal Tracking** → Usage vs limit calculated
3. **Points Awarded** → Based on efficiency + streak
4. **Tier Check** → Automatic tier upgrade if points reach threshold
5. **Achievements** → Unlocked when conditions met
6. **Socket.io Emit** → 'reward_update' sent to Flutter app

## Example Progression

```
Day 1: Used 2.5/5 kWh → 25 points (Bronze ⚡)
Day 2: Used 2.5/5 kWh → 32 points (7-day streak bonus)
Day 3: Used 2.0/5 kWh → 50 points (30% efficiency!)
Day 4: Used 6.0/5 kWh → 0 points (exceeded ❌)
Day 5: Used 2.5/5 kWh → 25 points (streak reset)
...
Week Total: ~160 points → Tier: Silver 🥈
```

## 🚗 Real-World Analogy

Like **airline frequent flyer programs**:
- Earn miles (points) for flying (efficient usage)
- Unlock status badges (achievements)
- Progress through tiers (Bronze → Platinum)
- Compete on leaderboard (miles ranking)

## ⚡ Innovation Points

✅ Gamifies energy conservation  
✅ Automatic point calculation  
✅ Streak-based motivation  
✅ Community leaderboards  
✅ Tier system with progression  
✅ 8 different achievements  
✅ Real-time Socket.io updates  
✅ Complete analytics history  

## 🎓 Faculty Demo Script

```bash
# 1. Show user rewards
curl http://192.168.184.49:4000/api/rewards/11

# 2. Show all achievements available
curl http://192.168.184.49:4000/api/rewards/achievements

# 3. Show leaderboard
curl http://192.168.184.49:4000/api/rewards/leaderboard?limit=5

# 4. Show 7-day points history
curl http://192.168.184.49:4000/api/rewards/history/11?days=7

# 5. Demonstrate Socket.io live update
# Turn on high-power appliance, monitor reward_update events
```

## 💡 Key Selling Points

1. **Behavioral Science**: Gamification proven to increase engagement
2. **Real-Time Feedback**: Instant point display (motivation)
3. **Social Competition**: Leaderboard drives community action
4. **Continuous Improvement**: Streaks incentivize consistency
5. **Innovation**: Most smart meters ignore behavioral aspects

This transforms energy monitoring from **passive tracking** → **active engagement**
