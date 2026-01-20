const express = require('express');
const router = express.Router();

// POST /api/notifications/log-anomaly - Log anomaly detection
router.post('/log-anomaly', async (req, res) => {
  try {
    const { anomalyType, voltage, current, power, timestamp } = req.body;

    // Log anomaly to database
    const anomalyLog = {
      type: anomalyType,
      voltage,
      current,
      power,
      timestamp: timestamp || new Date().toISOString(),
      notificationSent: true,
    };

    // In production, save to database
    console.log('📊 Anomaly logged:', anomalyLog);

    res.json({
      success: true,
      message: 'Anomaly logged successfully',
      anomaly: anomalyLog,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/notifications/log-bill-prediction - Log bill prediction alert
router.post('/log-bill-prediction', async (req, res) => {
  try {
    const { predictedBill, currentBill, riskLevel, timestamp } = req.body;

    const billLog = {
      predictedBill,
      currentBill,
      riskLevel,
      timestamp: timestamp || new Date().toISOString(),
      notificationSent: true,
    };

    // In production, save to database
    console.log('💰 Bill prediction logged:', billLog);

    res.json({
      success: true,
      message: 'Bill prediction logged successfully',
      bill: billLog,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/notifications/history/:userId - Get notification history
router.get('/history/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 20, type } = req.query;

    // In production, query notifications from database
    const notifications = [];

    res.json({
      success: true,
      notifications,
      total: notifications.length,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/notifications/clear - Clear notifications
router.post('/clear', async (req, res) => {
  try {
    const { userId } = req.body;

    // In production, delete notifications from database
    console.log(`🧹 Cleared notifications for user ${userId}`);

    res.json({
      success: true,
      message: 'Notifications cleared',
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST /api/notifications/preferences - Update notification preferences
router.post('/preferences', async (req, res) => {
  try {
    const {
      userId,
      anomalyAlerts,
      billAlerts,
      summaryNotifications,
      relayAlerts,
    } = req.body;

    const preferences = {
      userId,
      anomalyAlerts: anomalyAlerts ?? true,
      billAlerts: billAlerts ?? true,
      summaryNotifications: summaryNotifications ?? true,
      relayAlerts: relayAlerts ?? true,
      updatedAt: new Date().toISOString(),
    };

    // In production, save to database
    console.log('⚙️ Notification preferences updated:', preferences);

    res.json({
      success: true,
      message: 'Preferences saved',
      preferences,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/notifications/preferences/:userId - Get notification preferences
router.get('/preferences/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    // In production, get from database
    const preferences = {
      userId,
      anomalyAlerts: true,
      billAlerts: true,
      summaryNotifications: true,
      relayAlerts: true,
    };

    res.json({
      success: true,
      preferences,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
