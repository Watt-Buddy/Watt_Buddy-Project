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
