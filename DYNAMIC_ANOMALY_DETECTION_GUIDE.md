# Dynamic Anomaly Detection System - Implementation Guide

## Overview

The WattBuddy system now uses **intelligent, adaptive anomaly detection** based on each user's historical electricity usage patterns. Instead of fixed thresholds, the system learns what's "normal" for each user and alerts only when usage significantly deviates from that baseline.

## Key Components

### 1. **Daily Usage Aggregation**
- **Database Table**: `daily_usage`
  - Stores: `user_id`, `usage_date`, `total_kwh`, `avg_power`, `peak_power`
  - Auto-populated from `EnergyReadings` when ESP32 sends data
  - Aggregated daily via cron job at midnight

### 2. **User Baseline Statistics**
- Computed from last 30 days of `daily_usage` data
- Metrics:
  - **Mean Power**: Average daily power consumption
  - **Standard Deviation**: Measure of variation
  - **Dynamic Threshold**: `mean + (2 × stddev)` for 95% confidence
  - **95th Percentile**: Alternative threshold for sensitivity
  - **Z-Score**: Measures how many standard deviations current usage is from mean

### 3. **Anomaly Detection**
- **Method**: Statistical Z-score analysis
- **Threshold**: Dynamic, computed from user's historical data
- **Severity Levels**:
  - **Normal**: Z-score < 2
  - **Moderate**: Z-score 2-3
  - **High**: Z-score > 3

## Architecture

```
ESP32 → POST /esp32/update → Save EnergyReadings
                          ↓
                    Aggregate Daily Usage
                          ↓
                    Compute Baseline Stats
                          ↓
                    Dynamic Anomaly Detection
                          ↓
                    WebSocket Alert to Flutter App
```

## API Endpoints

### Daily Usage Management

#### 1. Backfill Historical Data
```bash
POST /api/usage/backfill/:userId
Body: { "daysBack": 90 }
```
Populates `daily_usage` table from historical `EnergyReadings`. Run this once after deployment.

**Example:**
```bash
curl -X POST http://192.168.184.49:4000/api/usage/backfill/8 \
  -H "Content-Type: application/json" \
  -d '{"daysBack": 90}'
```

#### 2. Get User Baseline
```bash
GET /api/usage/baseline/:userId
```
Returns statistical baseline for anomaly detection.

**Response:**
```json
{
  "success": true,
  "baseline": {
    "mean": 85.5,
    "stddev": 22.3,
    "threshold": 130.1,
    "p95": 125.0,
    "sampleSize": 30,
    "min": 45.0,
    "max": 150.0,
    "isDefault": false
  }
}
```

#### 3. Aggregate Today's Usage
```bash
POST /api/usage/aggregate-today/:userId
```
Manually triggers aggregation for today. (Auto-runs on ESP32 data save)

#### 4. Get Daily History
```bash
GET /api/usage/daily-history/:userId
```
Returns current month's daily usage for bar chart.

**Response:**
```json
[
  { "day": 1, "kwh": 2.45 },
  { "day": 2, "kwh": 3.12 },
  ...
  { "day": 15, "kwh": 2.89 }
]
```

### Updated Endpoints

#### Usage Summary (Now with Dynamic Anomaly)
```bash
GET /api/usage/summary/:userId
```

**Response:**
```json
{
  "success": true,
  "currentMonthKwh": 45.67,
  "lastMonthKwh": 52.34,
  "historicalAvgPower": 85.5,
  "daysElapsed": 15,
  "isAbnormal": true,
  "anomalySocket": "Socket 1",
  "currentPower": 165.0,
  "anomalyThreshold": 130.1
}
```

## Database Schema

### `daily_usage` Table
```sql
CREATE TABLE IF NOT EXISTS daily_usage (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  usage_date DATE,
  total_kwh FLOAT DEFAULT 0,
  avg_power FLOAT DEFAULT 0,
  peak_power FLOAT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, usage_date)
);
```

## Automated Jobs

### 1. Daily Aggregation Cron (Midnight)
```javascript
cron.schedule('0 0 * * *', ...)
```
Aggregates previous day's usage into `daily_usage` for all users.

### 2. Real-time Aggregation
Triggered on every ESP32 data save (when writing to DB).

## Testing

### Using Test Script

```bash
cd wattbuddy-server

# Backfill 90 days of historical data
node test_daily_analytics.js backfill 8 90

# Get baseline statistics
node test_daily_analytics.js baseline 8

# Check if 150W is anomalous
node test_daily_analytics.js detect 8 150

# Get daily history
node test_daily_analytics.js history 8 30

# Get current month data
node test_daily_analytics.js month 8
```

### Manual API Testing

```bash
# 1. Backfill historical data
curl -X POST http://192.168.184.49:4000/api/usage/backfill/8 \
  -H "Content-Type: application/json" \
  -d '{"daysBack": 90}'

# 2. Check baseline
curl http://192.168.184.49:4000/api/usage/baseline/8

# 3. Get daily history (for bar chart)
curl http://192.168.184.49:4000/api/usage/daily-history/8

# 4. Get summary with anomaly detection
curl http://192.168.184.49:4000/api/usage/summary/8
```

## How It Works

### Step 1: Data Collection
- ESP32 sends readings every 5 seconds → cached in memory
- Every 1 minute OR when energy changes ≥ 0.001 kWh → saved to `EnergyReadings`
- After saving → automatically aggregates into `daily_usage`

### Step 2: Baseline Computation
- Queries last 30 days from `daily_usage`
- Computes: mean, standard deviation, 95th percentile
- Calculates dynamic threshold: `mean + (2 × stddev)`
- If no historical data → uses safe defaults (mean=75W, threshold=150W)

### Step 3: Anomaly Detection
- On each reading, compares current power to dynamic threshold
- Calculates Z-score: `(current - mean) / stddev`
- If current > threshold → anomaly detected
- Emits WebSocket alert to Flutter app with severity level

### Step 4: Continuous Learning
- Daily aggregation updates `daily_usage` with latest data
- Baseline statistics automatically reflect recent usage patterns
- System adapts to seasonal changes, new appliances, lifestyle shifts

## Benefits

### Before (Fixed Threshold)
- ❌ Hardcoded `threshold = baseline × 2.0`
- ❌ Same threshold for all users regardless of usage patterns
- ❌ Many false positives or missed anomalies
- ❌ No adaptation to user behavior

### After (Dynamic Learning)
- ✅ Personalized threshold per user
- ✅ Based on statistical analysis (Z-score, percentiles)
- ✅ Adapts to user's changing patterns
- ✅ Severity levels (normal/moderate/high)
- ✅ ML-ready foundation for advanced predictions

## Migration Steps

### 1. Initial Setup (First Time)
```bash
# Start server
cd wattbuddy-server
npm start

# In another terminal, backfill historical data
node test_daily_analytics.js backfill 8 90
```

### 2. Verify Baseline
```bash
# Check if baseline computed correctly
node test_daily_analytics.js baseline 8

# Should show:
# Mean Power: ~75-100W (depends on your usage)
# Threshold: mean + 2×stddev
# Sample Size: Number of days with data
```

### 3. Test Anomaly Detection
```bash
# Test with normal power (should be normal)
node test_daily_analytics.js detect 8 80

# Test with high power (should be anomaly)
node test_daily_analytics.js detect 8 200
```

### 4. Monitor Flutter App
- Check bill prediction screen for bar chart (now uses `daily_usage`)
- Trigger appliance with high power consumption
- Verify WebSocket anomaly alert appears

## Troubleshooting

### "No historical data" / Using defaults
**Solution**: Run backfill to populate `daily_usage`:
```bash
node test_daily_analytics.js backfill 8 90
```

### Bar chart shows zeros
**Solution**: 
1. Backfill data first
2. Wait for ESP32 to send data
3. Check `/api/usage/daily-history/8` returns data

### Anomaly not triggering
**Solution**:
1. Check baseline: `node test_daily_analytics.js baseline 8`
2. Verify current power > threshold
3. Check WebSocket connection in Flutter app

### Daily aggregation not running
**Solution**:
1. Verify cron job is active (check server logs at midnight)
2. Manually trigger: `curl -X POST http://192.168.184.49:4000/api/usage/aggregate-today/8`

## Code Files Modified

### Backend
- `wattbuddy-server/services/dailyAnalyticsService.js` - **NEW** - Core analytics logic
- `wattbuddy-server/server.js` - Updated:
  - Added daily aggregation on ESP32 data save
  - Updated `/api/usage/daily-history` to use `daily_usage`
  - Updated `/api/usage/summary` with dynamic anomaly detection
  - Added 3 new endpoints (backfill, baseline, aggregate-today)
  - Added daily aggregation cron job

### Database
- `wattbuddy-server/init.sql` - Already had `daily_usage` table (no changes needed)

### Testing
- `wattbuddy-server/test_daily_analytics.js` - **NEW** - Test script for all features

## Next Steps (Future Enhancements)

1. **Seasonal Analysis**: Detect patterns by time of year
2. **Time-of-Day Profiles**: Different baselines for morning/evening/night
3. **Predictive Alerts**: Warn before exceeding monthly limit
4. **Appliance Fingerprinting**: Auto-identify devices by power signature
5. **Cost Optimization**: Suggest usage shifts to cheaper time periods

## Support

For issues or questions:
1. Check server logs: `wattbuddy-server/server_output.txt`
2. Run test script to diagnose: `node test_daily_analytics.js`
3. Verify ESP32 connectivity: `http://192.168.184.203/status`
4. Check database: `psql -U postgres -d wattbuddy -c "SELECT * FROM daily_usage LIMIT 10;"`
