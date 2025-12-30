// 🔔 FEATURE 1: Power-Limit Notification Service
const db = require('../db');

class PowerLimitService {
  // Check power usage against limits and send notifications
  static async checkPowerLimit(userId, currentUsage, dailyLimit) {
    try {
      const thresholds = [50, 75, 90, 100];
      const usagePercentage = (currentUsage / dailyLimit) * 100;

      for (const threshold of thresholds) {
        if (usagePercentage >= threshold) {
          const severity = threshold === 100 ? 'critical' : threshold === 90 ? 'high' : 'warning';
          const title = threshold === 100 ? '🚨 Power Limit Exceeded!' : `⚠️ Warning: ${threshold}% Usage`;
          
          const message = `Your power usage has reached ${usagePercentage.toFixed(1)}% of daily limit (${currentUsage.toFixed(2)}W / ${dailyLimit.toFixed(2)}W)`;

          // Create notification
          await db.query(
            `INSERT INTO notifications 
             (user_id, type, title, message, severity, data)
             VALUES ($1, $2, $3, $4, $5, $6)`,
            [
              userId,
              'power_limit_alert',
              title,
              message,
              severity,
              JSON.stringify({
                current_usage: currentUsage,
                limit: dailyLimit,
                percentage: usagePercentage,
                threshold,
                timestamp: new Date().toISOString()
              })
            ]
          );

          console.log(`✅ Power limit notification sent to user ${userId}: ${threshold}%`);
          return { notificationSent: true, threshold, percentage: usagePercentage };
        }
      }
      return { notificationSent: false };
    } catch (error) {
      console.error('❌ Error checking power limit:', error);
      throw error;
    }
  }

  // Get user's power limit settings
  static async getPowerLimitSettings(userId) {
    try {
      const result = await db.query(
        `SELECT daily_power_limit, alert_threshold 
         FROM user_settings WHERE user_id = $1`,
        [userId]
      );

      return result.rows[0] || { daily_power_limit: 5000, alert_threshold: 0.75 };
    } catch (error) {
      console.error('❌ Error fetching power limit settings:', error);
      return { daily_power_limit: 5000, alert_threshold: 0.75 };
    }
  }

  // Set power limit for user
  static async setPowerLimit(userId, dailyLimit) {
    try {
      const result = await db.query(
        `INSERT INTO user_settings (user_id, daily_power_limit)
         VALUES ($1, $2)
         ON CONFLICT (user_id) 
         DO UPDATE SET daily_power_limit = $2
         RETURNING *`,
        [userId, dailyLimit]
      );

      console.log(`✅ Power limit set for user ${userId}: ${dailyLimit}W`);
      return result.rows[0];
    } catch (error) {
      console.error('❌ Error setting power limit:', error);
      throw error;
    }
  }
}

module.exports = PowerLimitService;
