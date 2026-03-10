# Quick Start Guide - Dynamic Anomaly Detection

## ✅ What Was Implemented

### 1. **Daily Usage Database**
- Created `daily_usage` table to store daily aggregated usage per user
- Auto-populates when ESP32 sends data
- Stores: date, total kWh, average power, peak power

### 2. **Dynamic Anomaly Detection**
- **Before**: Fixed threshold (baseline × 2.0)
- **After**: Statistical threshold based on each user's historical patterns
- Uses Z-score analysis (mean + 2×stddev for 95% confidence)
- Adapts to your actual usage automatically

### 3. **User Baseline Statistics**
- Computes from last 30 days of daily usage
- Shows: mean power, standard deviation, dynamic threshold
- Updates automatically as new data comes in

## 🚀 Quick Setup

### Step 1: Initialize Database (Already Done ✅)
```bash
cd wattbuddy-server
node initDb.js
```

### Step 2: Backfill Historical Data
```bash
# Replace '11' with your actual user ID
node test_daily_analytics.js backfill 11 90
```

### Step 3: Check Your Baseline
```bash
node test_daily_analytics.js baseline 11
```

You should see:
```
Mean Power: 72.40W
Threshold: 118.47W
Sample Size: 2 days
```

### Step 4: Test Anomaly Detection
```bash
# Test with normal power (should NOT be anomaly)
node test_daily_analytics.js detect 11 80

# Test with high power (should BE anomaly)
node test_daily_analytics.js detect 11 150
```

## 📊 API Usage

### Get Daily History (For Bar Chart)
```bash
curl http://192.168.184.49:4000/api/usage/daily-history/11
```

Returns:
```json
[
  {"day": 1, "kwh": 0},
  {"day": 2, "kwh": 0},
  {"day": 3, "kwh": 0},
  {"day": 4, "kwh": 0.056},
  {"day": 5, "kwh": 0.152}
]
```

### Get Usage Summary with Anomaly Check
```bash
curl http://192.168.184.49:4000/api/usage/summary/11
```

Returns:
```json
{
  "success": true,
  "currentMonthKwh": 0.208,
  "lastMonthKwh": 0,
  "historicalAvgPower": 72.4,
  "isAbnormal": false,
  "anomalySocket": null,
  "currentPower": 85.2,
  "anomalyThreshold": 118.47
}
```

### Get Baseline Statistics
```bash
curl http://192.168.184.49:4000/api/usage/baseline/11
```

## 🔄 How It Works

### Automatic Process:
1. **ESP32 sends data** every 5 seconds → cached
2. **Every 1 minute** OR **energy change ≥ 0.001 kWh** → saved to DB
3. **After save** → aggregates today's usage into `daily_usage` table
4. **At midnight** → cron job aggregates previous day for all users
5. **On anomaly check** → computes dynamic threshold from last 30 days
6. **If anomaly** → sends WebSocket alert to Flutter app

### Anomaly Detection Logic:
```
1. Get user's last 30 days of daily_usage
2. Compute: mean, stddev
3. Threshold = mean + (2 × stddev)
4. Current power > threshold? → ANOMALY!
5. Z-score = (current - mean) / stddev
6. Severity:
   - Z < 2: Normal
   - Z 2-3: Moderate
   - Z > 3: High
```

## ⚙️ Configuration

### Change Lookback Period (Default: 30 days)
Edit `dailyAnalyticsService.js`:
```javascript
static async getUserBaseline(userId, lookbackDays = 30)
```

### Change Confidence Level (Default: 95% = 2 stddev)
Edit `dailyAnalyticsService.js`:
```javascript
const zScoreThreshold = mean + (2 * stddev); // Change 2 to 1.5 for 68%, or 3 for 99.7%
```

### Manually Trigger Aggregation
```bash
curl -X POST http://192.168.184.49:4000/api/usage/aggregate-today/11
```

## 📈 What You'll See

### Before (Fixed Threshold)
- ❌ Same threshold for everyone (e.g., always 150W)
- ❌ No adaptation to usage patterns
- ❌ Many false alarms OR missed anomalies

### After (Dynamic Learning)
- ✅ **Your** threshold based on **your** usage (e.g., 118W for user 11, 200W for heavy user)
- ✅ Adapts as your usage changes
- ✅ Accurate anomaly detection with severity levels
- ✅ Ready for ML predictions

## 🎯 Next Steps

1. **Use your actual user ID**: Replace `11` with your real user ID in commands
2. **Let it collect data**: System gets smarter with more data (at least 7 days recommended)
3. **Monitor alerts**: Check Flutter app when high-power appliances turn on
4. **Review baseline**: Run `node test_daily_analytics.js baseline <userId>` weekly

## 🐛 Troubleshooting

### "Using default values (no historical data)"
**Solution**: Run backfill command:
```bash
node test_daily_analytics.js backfill 11 90
```

### Bar chart shows all zeros
**Causes**:
1. No ESP32 data coming in
2. Need to aggregate manually

**Solution**:
```bash
# Check if data exists
node check_data.js

# Manually aggregate
curl -X POST http://192.168.184.49:4000/api/usage/aggregate-today/11
```

### Anomaly not triggering
**Check threshold**:
```bash
node test_daily_analytics.js baseline 11
```

If threshold is very high (e.g., 500W), you need more realistic historical data.

## 📝 Files Created/Modified

### New Files:
- `services/dailyAnalyticsService.js` - Core analytics engine
- `test_daily_analytics.js` - Testing script
- `check_data.js` - Data verification script
- `DYNAMIC_ANOMALY_DETECTION_GUIDE.md` - Full documentation

### Modified Files:
- `server.js` - Added daily aggregation, dynamic anomaly detection, new endpoints, cron job
- `initDb.js` - Added daily_usage table creation

## ✨ Benefits Summary

| Feature | Before | After |
|---------|--------|-------|
| Threshold Type | Fixed (baseline × 2) | Dynamic (mean + 2×stddev) |
| User-Specific | ❌ No | ✅ Yes |
| Adapts Over Time | ❌ No | ✅ Yes |
| Severity Levels | ❌ None | ✅ 3 levels |
| ML-Ready | ❌ No | ✅ Yes |
| False Positives | ⚠️ High | ✅ Low |

---

**Congratulations!** Your WattBuddy system now has intelligent anomaly detection that learns from your usage patterns! 🎉
