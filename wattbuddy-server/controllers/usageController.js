const MonthlyUsageService = require('../services/monthlyUsageService');
const moment = require('moment');

// Update daily usage
exports.updateDailyUsage = async (req, res) => {
  const { userId, dailyKwh, usageDate } = req.body;

  if (!userId || !dailyKwh) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    const result = await MonthlyUsageService.updateDailyUsage(userId, dailyKwh, usageDate);

    res.json({
      success: true,
      message: 'Daily usage updated',
      data: result,
    });
  } catch (error) {
    console.error('❌ Error updating daily usage:', error);
    res.status(500).json({ error: error.message });
  }
};

// Get monthly usage summary
exports.getMonthlyUsageSummary = async (req, res) => {
  const { userId } = req.params;
  const { monthYear } = req.query;

  try {
    const summary = await MonthlyUsageService.getMonthlyUsageSummary(userId, monthYear);

    res.json({
      success: true,
      summary,
    });
  } catch (error) {
    console.error('❌ Error fetching monthly summary:', error);
    res.status(500).json({ error: error.message });
  }
};

// Set monthly limit
exports.setMonthlyLimit = async (req, res) => {
  const { userId, limitKwh } = req.body;

  if (!userId || !limitKwh) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  try {
    const result = await MonthlyUsageService.setMonthlyLimit(userId, limitKwh);

    res.json({
      success: true,
      message: 'Monthly limit updated',
      data: result,
    });
  } catch (error) {
    console.error('❌ Error setting monthly limit:', error);
    res.status(500).json({ error: error.message });
  }
};

// Get monthly limit
exports.getMonthlyLimit = async (req, res) => {
  const { userId } = req.params;

  try {
    const limit = await MonthlyUsageService.getMonthlyLimit(userId);

    res.json({
      success: true,
      monthlyLimit: limit,
    });
  } catch (error) {
    console.error('❌ Error fetching monthly limit:', error);
    res.status(500).json({ error: error.message });
  }
};

// Get daily usage stats
exports.getDailyUsageStats = async (req, res) => {
  const { userId } = req.params;
  const { days = 30 } = req.query;

  try {
    const db = require('../db');
    const startDate = moment().subtract(days, 'days').format('YYYY-MM-DD');

    const result = await db.query(
      `SELECT usage_date, total_kwh 
       FROM daily_usage
       WHERE user_id = $1 AND usage_date >= $2
       ORDER BY usage_date DESC`,
      [userId, startDate]
    );

    const stats = {
      totalDays: result.rows.length,
      averageDaily: result.rows.reduce((sum, r) => sum + r.total_kwh, 0) / (result.rows.length || 1),
      maxDaily: Math.max(...result.rows.map(r => r.total_kwh), 0),
      minDaily: Math.min(...result.rows.map(r => r.total_kwh), 0),
      trend: result.rows,
    };

    res.json({
      success: true,
      stats,
    });
  } catch (error) {
    console.error('❌ Error fetching daily stats:', error);
    res.status(500).json({ error: error.message });
  }
};

// Get usage alerts
exports.getUsageAlerts = async (req, res) => {
  const { userId } = req.params;
  const { limit = 10 } = req.query;

  try {
    const db = require('../db');

    const result = await db.query(
      `SELECT * FROM usage_alerts
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [userId, limit]
    );

    res.json({
      success: true,
      alerts: result.rows,
    });
  } catch (error) {
    console.error('❌ Error fetching usage alerts:', error);
    res.status(500).json({ error: error.message });
  }
};

// Acknowledge/resolve alert
exports.resolveAlert = async (req, res) => {
  const { alertId } = req.body;

  if (!alertId) {
    return res.status(400).json({ error: 'Missing alertId' });
  }

  try {
    const db = require('../db');

    const result = await db.query(
      `UPDATE usage_alerts
       SET is_resolved = true
       WHERE id = $1
       RETURNING *`,
      [alertId]
    );

    res.json({
      success: true,
      message: 'Alert resolved',
      data: result.rows[0],
    });
  } catch (error) {
    console.error('❌ Error resolving alert:', error);
    res.status(500).json({ error: error.message });
  }
};

// Get usage forecast
exports.getUsageForecast = async (req, res) => {
  const { userId } = req.params;

  try {
    const db = require('../db');

    // Get average daily usage from last 7 days
    const weekAgoResult = await db.query(
      `SELECT AVG(total_kwh) as avg_daily_usage
       FROM daily_usage
       WHERE user_id = $1 AND usage_date >= NOW()::date - INTERVAL '7 days'`,
      [userId]
    );

    const avgDailyUsage = weekAgoResult.rows[0]?.avg_daily_usage || 10;

    // Get remaining days in month
    const today = moment();
    const endOfMonth = moment().endOf('month');
    const remainingDays = endOfMonth.diff(today, 'days');

    // Get current month summary
    const monthYear = today.format('YYYY-MM');
    const monthlyRecord = await MonthlyUsageService.getOrCreateMonthlyUsage(userId, monthYear);

    // Calculate projected usage
    const projectedUsage = monthlyRecord.consumed_kwh + avgDailyUsage * remainingDays;
    const projectedRemaining = monthlyRecord.allocated_kwh - projectedUsage;
    const willExceed = projectedRemaining < 0;

    res.json({
      success: true,
      forecast: {
        averageDailyUsage: avgDailyUsage.toFixed(2),
        remainingDaysInMonth: remainingDays,
        currentConsumption: monthlyRecord.consumed_kwh.toFixed(2),
        monthlyLimit: monthlyRecord.allocated_kwh.toFixed(2),
        projectedUsage: projectedUsage.toFixed(2),
        projectedRemaining: projectedRemaining.toFixed(2),
        willExceed,
        projectedExcess: willExceed ? Math.abs(projectedRemaining).toFixed(2) : 0,
      },
    });
  } catch (error) {
    console.error('❌ Error calculating forecast:', error);
    res.status(500).json({ error: error.message });
  }
};

// ============ NEW: Get usage summary for bill predictor ============
// Fetches current month, last month, and historical average power consumption
exports.getUsageSummary = async (req, res) => {
  const { userId } = req.params;

  try {
    const db = require('../db');

    // Query combining current month, last month, and historical averages
    const query = `
      SELECT 
        COALESCE(SUM(CASE WHEN timestamp >= DATE_TRUNC('month', CURRENT_DATE) 
                         THEN energy_consumed ELSE 0 END), 0) as current_month_kwh,
        COALESCE(SUM(CASE WHEN timestamp >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month') 
                         AND timestamp < DATE_TRUNC('month', CURRENT_DATE) 
                         THEN energy_consumed ELSE 0 END), 0) as last_month_kwh,
        COALESCE(AVG(power), 0) as historical_avg_power,
        COALESCE(MAX(power), 0) as peak_power,
        COALESCE(COUNT(*), 0) as readings_this_month
      FROM "EnergyReadings"
      WHERE user_id = $1
    `;

    const result = await db.query(query, [userId]);
    const data = result.rows[0];

    // Get current live power from cache (exported from server.js)
    let { esp32LatestData } = require('../server');
    const currentPower = esp32LatestData.power || 0;
    // Baseline average (use your logs as baseline if no historical data)
    const avgPower = parseFloat(data.historical_avg_power) || 75;

    // Demo logic: trigger only for strong anomalies (>= 2x)
    let isAbnormal = false;
    let anomalySocket = "None";

    if (currentPower > (avgPower * 2.0)) {
      isAbnormal = true;

      // Pinpoint likely socket by relay states
      if (esp32LatestData.relay1 === 1 && esp32LatestData.relay2 === 0) anomalySocket = "Socket 1";
      else if (esp32LatestData.relay2 === 1 && esp32LatestData.relay1 === 0) anomalySocket = "Socket 2";
      else anomalySocket = "Both Sockets";

      console.log(`\u26a0\ufe0f DEMO-ANOMALY: Current ${currentPower}W >= 2x Avg ${avgPower}W | Source: ${anomalySocket}`);
    }

    // Calculate days elapsed in current month
    const today = moment();
    const daysElapsed = today.date();
    const daysInMonth = today.daysInMonth();

    // Calculate predicted usage for current month (based on daily average)
    const dailyAverageThisMonth = daysElapsed > 0 
      ? data.current_month_kwh / daysElapsed 
      : 0;
    const predictedMonthlyKwh = dailyAverageThisMonth * daysInMonth;

    // Calculate month-over-month change
    const monthChange = data.last_month_kwh > 0 
      ? ((data.current_month_kwh - data.last_month_kwh) / data.last_month_kwh * 100).toFixed(1)
      : 0;

    res.json({
      success: true,
      isAbnormal: isAbnormal,
      anomalySocket: anomalySocket,
      currentMonthKwh: parseFloat(data.current_month_kwh) || 0,
      lastMonthKwh: parseFloat(data.last_month_kwh) || 0,
      historicalAvgPower: parseFloat(data.historical_avg_power) || 0,
      currentPower: currentPower,
      peakPowerRecorded: parseFloat(data.peak_power) || 0,
      readingsThisMonth: parseInt(data.readings_this_month) || 0,
      daysElapsed: daysElapsed,
      daysInMonth: daysInMonth,
      dailyAverageThisMonth: dailyAverageThisMonth.toFixed(2),
      predictedMonthlyKwh: predictedMonthlyKwh.toFixed(2),
      monthOverMonthChangePercent: monthChange,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('❌ Error fetching usage summary:', err);
    res.status(500).json({ success: false, error: err.message });
  }
};
