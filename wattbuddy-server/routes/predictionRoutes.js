const express = require('express');
const router = express.Router();
const pool = require('../db');

const BASE_CHARGE = 50;
const RATE_PER_KWH = 10;

// Prediction endpoints
// GET /api/predictions/bill/:userId - Get predicted next month bill
router.get('/bill/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const currentUsage = await getCurrentMonthUsage(userId);
    const lastMonthUsage = await getLastMonthUsage(userId);
    const { currentBill, source } = await getCurrentBill(userId, currentUsage);

    const now = new Date();
    const daysElapsed = now.getDate();
    const totalDaysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();

    // Predict end-of-next-month usage from real month-to-date pace + last month trend.
    const avgDailyUsage = daysElapsed > 0 ? currentUsage / daysElapsed : 0;
    const paceProjection = avgDailyUsage * totalDaysInMonth;
    const trendWeightedProjection = lastMonthUsage > 0
      ? (paceProjection * 0.7) + (lastMonthUsage * 0.3)
      : paceProjection;
    const predictedUsage = Number(Math.max(0, trendWeightedProjection).toFixed(3));
    const predictedBill = calculateBill(predictedUsage);

    // Determine risk level
    const denominator = currentBill > 0 ? currentBill : 1;
    const percentageChange = ((predictedBill - currentBill) / denominator) * 100;
    let riskLevel = 'Low';
    if (percentageChange > 25) riskLevel = 'High';
    else if (percentageChange > 10) riskLevel = 'Medium';

    res.json({
      success: true,
      prediction: {
        predictedBill: Number(predictedBill.toFixed(2)),
        predictedUsage,
        currentBill: Number(currentBill.toFixed(2)),
        currentUsage: Number(currentUsage.toFixed(3)),
        lastMonthUsage: Number(lastMonthUsage.toFixed(3)),
        daysElapsed,
        totalDaysInMonth,
        currentBillSource: source,
        riskLevel,
        percentageChange: Number(percentageChange.toFixed(2)),
        timestamp: new Date().toISOString(),
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/predictions/30days/:userId - Get 30-day consumption predictions
router.get('/30days/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const predictions = await predictNext30DaysFromHistory(userId);

    res.json({
      success: true,
      predictions,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/predictions/breakdown/:userId - Get bill breakdown by appliance
router.get('/breakdown/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    // Estimated usage split by relay states from EnergyReadings deltas
    const breakdown = await getApplianceBreakdown(userId);

    res.json({
      success: true,
      breakdown: {
        appliances: breakdown.appliances,
        topConsumer: breakdown.topConsumer,
        topConsumerUsage: breakdown.topConsumerUsage,
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/predictions/recommendations/:userId - Get energy saving recommendations
router.get('/recommendations/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const recommendations = [
      'Shift AC usage to night hours (9 PM - 6 AM) for lower rates',
      'Reduce water heater temperature by 2-3 degrees',
      'Switch off appliances when not in use',
      'Use LED bulbs instead of incandescent',
      'Avoid running AC and water heater simultaneously',
      'Check for refrigerator leaks causing excess cooling',
      'Use fan instead of AC during mild weather',
      'Set AC temperature to 24°C instead of 22°C',
    ];

    // Get personalized recommendations based on user's real usage stats
    const personalizedRecs = await getPersonalizedRecommendations(userId);

    res.json({
      success: true,
      recommendations: personalizedRecs.length > 0 ? personalizedRecs : recommendations,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============ HELPER FUNCTIONS ============

async function getCurrentMonthUsage(userId) {
  try {
    const MonthlySnapshotService = require('../services/monthlySnapshotService');
    return await MonthlySnapshotService.getCurrentMonthUsage(userId);
  } catch (err) {
    console.warn('⚠️ Snapshot method failed in predictionRoutes, using MAX-MIN:', err);
    // Fallback to old method
    const query = `
      SELECT COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) AS kwh
      FROM "EnergyReadings"
      WHERE user_id = $1::text
        AND timestamp >= DATE_TRUNC('month', CURRENT_DATE)
    `;
    const result = await pool.query(query, [userId]);
    return parseFloat(result.rows?.[0]?.kwh || 0);
  }
}

async function getLastMonthUsage(userId) {
  try {
    const MonthlySnapshotService = require('../services/monthlySnapshotService');
    const lastMonthDate = new Date();
    lastMonthDate.setMonth(lastMonthDate.getMonth() - 1);
    const month = lastMonthDate.getMonth() + 1;
    const year = lastMonthDate.getFullYear();
    return await MonthlySnapshotService.getMonthUsage(userId, year, month);
  } catch (err) {
    console.warn('⚠️ Snapshot method failed for last month in predictionRoutes, using MAX-MIN:', err);
    // Fallback to old method
    const query = `
      SELECT COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) AS kwh
      FROM "EnergyReadings"
      WHERE user_id = $1::text
        AND timestamp >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
        AND timestamp < DATE_TRUNC('month', CURRENT_DATE)
    `;
    const result = await pool.query(query, [userId]);
    return parseFloat(result.rows?.[0]?.kwh || 0);
  }
}

async function getCurrentBill(userId, currentUsage) {
  try {
    const fromView = await pool.query(
      'SELECT slab_bill_rs FROM view_user_bills WHERE user_id = $1::text LIMIT 1',
      [userId]
    );
    if (fromView.rows.length > 0) {
      return {
        currentBill: parseFloat(fromView.rows[0].slab_bill_rs || 0),
        source: 'view_user_bills',
      };
    }
  } catch (_) {
    // fall through to formula fallback
  }

  return {
    currentBill: calculateBill(currentUsage),
    source: 'fallback_formula',
  };
}

function calculateBill(usage) {
  return (usage * RATE_PER_KWH) + BASE_CHARGE;
}

async function predictNext30DaysFromHistory(userId) {
  const dailyQuery = `
    WITH daily AS (
      SELECT
        DATE(timestamp) AS day,
        EXTRACT(DOW FROM timestamp)::int AS dow,
        COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) AS kwh
      FROM "EnergyReadings"
      WHERE user_id = $1::text
        AND timestamp >= CURRENT_DATE - INTERVAL '60 days'
      GROUP BY DATE(timestamp), EXTRACT(DOW FROM timestamp)
    )
    SELECT day, dow, kwh
    FROM daily
    ORDER BY day DESC
  `;

  const result = await pool.query(dailyQuery, [userId]);
  const rows = result.rows || [];

  const dowBuckets = new Map();
  let sum = 0;
  let count = 0;

  for (const row of rows) {
    const dow = Number(row.dow);
    const kwh = Number(row.kwh || 0);
    sum += kwh;
    count += 1;

    if (!dowBuckets.has(dow)) dowBuckets.set(dow, []);
    dowBuckets.get(dow).push(kwh);
  }

  const globalAvg = count > 0 ? sum / count : 0.5;

  const predictions = [];
  for (let i = 1; i <= 30; i++) {
    const date = new Date();
    date.setDate(date.getDate() + i);
    const dow = date.getDay();
    const bucket = dowBuckets.get(dow) || [];
    const dowAvg = bucket.length > 0
      ? bucket.reduce((a, b) => a + b, 0) / bucket.length
      : globalAvg;

    predictions.push({
      day: i,
      predictedDailyEnergy: Number(Math.max(0, dowAvg).toFixed(3)),
      timestamp: date.toISOString(),
      basis: bucket.length > 0 ? 'same_weekday_average' : 'global_average',
    });
  }

  return predictions;
}

async function getApplianceBreakdown(userId) {
  const query = `
    WITH ordered AS (
      SELECT
        timestamp,
        energy_consumed,
        relay1,
        relay2,
        LAG(energy_consumed) OVER (ORDER BY timestamp) AS prev_energy
      FROM "EnergyReadings"
      WHERE user_id = $1::text
        AND timestamp >= DATE_TRUNC('month', CURRENT_DATE)
    ),
    deltas AS (
      SELECT
        relay1,
        relay2,
        GREATEST(0, LEAST(energy_consumed - prev_energy, 1.5)) AS delta_kwh
      FROM ordered
      WHERE prev_energy IS NOT NULL
    )
    SELECT
      COALESCE(SUM(CASE WHEN relay1 = 1 AND relay2 <> 1 THEN delta_kwh ELSE 0 END), 0) AS socket1_kwh,
      COALESCE(SUM(CASE WHEN relay2 = 1 AND relay1 <> 1 THEN delta_kwh ELSE 0 END), 0) AS socket2_kwh,
      COALESCE(SUM(CASE WHEN relay1 = 1 AND relay2 = 1 THEN delta_kwh ELSE 0 END), 0) AS both_kwh
    FROM deltas
  `;

  const result = await pool.query(query, [userId]);
  const row = result.rows?.[0] || {};

  const socket1 = parseFloat(row.socket1_kwh || 0);
  const socket2 = parseFloat(row.socket2_kwh || 0);
  const both = parseFloat(row.both_kwh || 0);
  const total = socket1 + socket2 + both;

  if (total <= 0) {
    return {
      appliances: [],
      topConsumer: 'No data',
      topConsumerUsage: 0,
    };
  }

  const appliances = [
    { name: 'Socket 1', usage: Number(socket1.toFixed(3)), percentage: Number(((socket1 / total) * 100).toFixed(1)) },
    { name: 'Socket 2', usage: Number(socket2.toFixed(3)), percentage: Number(((socket2 / total) * 100).toFixed(1)) },
    { name: 'Both Sockets', usage: Number(both.toFixed(3)), percentage: Number(((both / total) * 100).toFixed(1)) },
  ].sort((a, b) => b.usage - a.usage);

  return {
    appliances,
    topConsumer: appliances[0].name,
    topConsumerUsage: appliances[0].usage,
  };
}

async function getPersonalizedRecommendations(userId) {
  const query = `
    SELECT
      COALESCE(AVG(power), 0) AS avg_power,
      COALESCE(MAX(power), 0) AS peak_power,
      COUNT(*)::int AS points
    FROM "EnergyReadings"
    WHERE user_id = $1::text
      AND timestamp >= DATE_TRUNC('month', CURRENT_DATE)
  `;
  const result = await pool.query(query, [userId]);
  const row = result.rows?.[0] || {};

  const avgPower = parseFloat(row.avg_power || 0);
  const peakPower = parseFloat(row.peak_power || 0);
  const points = parseInt(row.points || 0, 10);

  const recs = [];

  if (points < 20) {
    recs.push('Keep device powered for longer daily periods to improve prediction accuracy.');
  }
  if (peakPower > 500) {
    recs.push('Your peak load is high; avoid running heavy appliances at the same time.');
  }
  if (avgPower > 200) {
    recs.push('Your average load is elevated; check always-on appliances for standby drain.');
  }
  if (recs.length === 0) {
    recs.push('Consumption pattern looks stable. Maintain current usage habits.');
    recs.push('Shift discretionary usage to off-peak hours for better tariff efficiency.');
  }

  return recs;
}

module.exports = router;
