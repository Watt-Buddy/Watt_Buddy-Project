const express = require('express');
const router = express.Router();
const {
  updateDailyUsage,
  getMonthlyUsageSummary,
  setMonthlyLimit,
  getMonthlyLimit,
  getDailyUsageStats,
  getUsageAlerts,
  resolveAlert,
  getUsageForecast,
  getUsageSummary,
} = require('../controllers/usageController');

// Daily usage
router.post('/daily-usage', updateDailyUsage);
router.get('/daily-stats/:userId', getDailyUsageStats);

// Monthly limits
router.get('/monthly-limit/:userId', getMonthlyLimit);
router.post('/monthly-limit', setMonthlyLimit);
router.get('/monthly-summary/:userId', getMonthlyUsageSummary);

// Usage alerts and notifications
router.get('/alerts/:userId', getUsageAlerts);
router.post('/alerts/resolve', resolveAlert);

// Forecast
router.get('/forecast/:userId', getUsageForecast);

// ============ NEW: Usage Summary for Bill Predictor ============
router.get('/summary/:userId', getUsageSummary);

module.exports = router;
