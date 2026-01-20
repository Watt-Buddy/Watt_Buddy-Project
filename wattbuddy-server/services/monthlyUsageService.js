const db = require('../db');
const moment = require('moment');

class MonthlyUsageService {
  /**
   * Get or create monthly usage record for a user
   */
  static async getOrCreateMonthlyUsage(userId, monthYear = null) {
    if (!monthYear) {
      monthYear = moment().format('YYYY-MM');
    }

    try {
      // Check if record exists
      const existing = await db.query(
        `SELECT * FROM monthly_usage 
         WHERE user_id = $1 AND month_year = $2`,
        [userId, monthYear]
      );

      if (existing.rows.length > 0) {
        return existing.rows[0];
      }

      // Get user's monthly limit
      const limitResult = await db.query(
        `SELECT monthly_limit_kwh FROM monthly_limits WHERE user_id = $1`,
        [userId]
      );

      const monthlyLimit = limitResult.rows[0]?.monthly_limit_kwh || 300;

      // Get carryover from previous month
      const previousMonth = moment(monthYear, 'YYYY-MM').subtract(1, 'month').format('YYYY-MM');
      const previousResult = await db.query(
        `SELECT carryover_to_next FROM monthly_usage 
         WHERE user_id = $1 AND month_year = $2`,
        [userId, previousMonth]
      );

      const carryoverFromPrevious = previousResult.rows[0]?.carryover_to_next || 0;
      const allocatedKwh = monthlyLimit + carryoverFromPrevious;

      // Create new monthly usage record
      const newRecord = await db.query(
        `INSERT INTO monthly_usage 
         (user_id, month_year, allocated_kwh, consumed_kwh, remaining_kwh, carryover_from_previous)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [userId, monthYear, allocatedKwh, 0, allocatedKwh, carryoverFromPrevious]
      );

      console.log(`✅ Created monthly usage record for user ${userId}, month ${monthYear}`);
      return newRecord.rows[0];
    } catch (error) {
      console.error('❌ Error getting/creating monthly usage:', error);
      throw error;
    }
  }

  /**
   * Update daily usage and check against monthly limit
   */
  static async updateDailyUsage(userId, dailyKwh, usageDate = null) {
    if (!usageDate) {
      usageDate = moment().format('YYYY-MM-DD');
    }

    try {
      // Update or create daily usage
      const dailyResult = await db.query(
        `INSERT INTO daily_usage (user_id, usage_date, total_kwh)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id, usage_date) 
         DO UPDATE SET total_kwh = $3
         RETURNING *`,
        [userId, usageDate, dailyKwh]
      );

      console.log(`✅ Updated daily usage for user ${userId}: ${dailyKwh} kWh`);

      // Get current month
      const monthYear = moment(usageDate).format('YYYY-MM');

      // Update monthly consumption
      await this.updateMonthlyConsumption(userId, monthYear);

      return dailyResult.rows[0];
    } catch (error) {
      console.error('❌ Error updating daily usage:', error);
      throw error;
    }
  }

  /**
   * Update monthly consumption and check limits
   */
  static async updateMonthlyConsumption(userId, monthYear) {
    try {
      // Sum all daily usage for the month
      const monthStart = moment(monthYear, 'YYYY-MM').startOf('month').format('YYYY-MM-DD');
      const monthEnd = moment(monthYear, 'YYYY-MM').endOf('month').format('YYYY-MM-DD');

      const usageResult = await db.query(
        `SELECT COALESCE(SUM(total_kwh), 0) as total_consumption
         FROM daily_usage
         WHERE user_id = $1 AND usage_date >= $2 AND usage_date <= $3`,
        [userId, monthStart, monthEnd]
      );

      const consumedKwh = usageResult.rows[0].total_consumption;

      // Get monthly usage record
      const monthlyRecord = await this.getOrCreateMonthlyUsage(userId, monthYear);

      const allocatedKwh = monthlyRecord.allocated_kwh;
      const remainingKwh = allocatedKwh - consumedKwh;
      const exceeded = remainingKwh < 0;
      const excessAmount = exceeded ? Math.abs(remainingKwh) : 0;

      // Update monthly usage
      const updateResult = await db.query(
        `UPDATE monthly_usage
         SET consumed_kwh = $1,
             remaining_kwh = $2,
             exceeded = $3,
             excess_amount = $4,
             updated_at = NOW()
         WHERE user_id = $5 AND month_year = $6
         RETURNING *`,
        [consumedKwh, remainingKwh, exceeded, excessAmount, userId, monthYear]
      );

      const updatedRecord = updateResult.rows[0];

      // Check if we need to send notification
      if (exceeded && !updatedRecord.notification_sent) {
        await this.sendExceededNotification(userId, updatedRecord);
      }

      return updatedRecord;
    } catch (error) {
      console.error('❌ Error updating monthly consumption:', error);
      throw error;
    }
  }

  /**
   * Send notification when limit is exceeded
   */
  static async sendExceededNotification(userId, monthlyRecord) {
    try {
      const thresholds = [50, 75, 90, 100];
      const usagePercentage = (monthlyRecord.consumed_kwh / monthlyRecord.allocated_kwh) * 100;

      for (const threshold of thresholds) {
        if (usagePercentage >= threshold) {
          const message = `⚠️ You've used ${usagePercentage.toFixed(1)}% of your monthly limit (${monthlyRecord.consumed_kwh.toFixed(2)}/${monthlyRecord.allocated_kwh.toFixed(2)} kWh)`;

          // Create usage alert
          await db.query(
            `INSERT INTO usage_alerts 
             (user_id, alert_type, threshold_percentage, current_usage, monthly_limit, message)
             VALUES ($1, $2, $3, $4, $5, $6)`,
            [
              userId,
              threshold === 100 ? 'exceeded' : 'approaching',
              threshold,
              monthlyRecord.consumed_kwh,
              monthlyRecord.allocated_kwh,
              message,
            ]
          );

          // Create notification
          await db.query(
            `INSERT INTO notifications
             (user_id, type, title, message, severity, data, is_read)
             VALUES ($1, $2, $3, $4, $5, $6, false)`,
            [
              userId,
              threshold === 100 ? 'usage_exceeded' : 'usage_warning',
              threshold === 100 ? '🚨 Monthly Limit Exceeded!' : '⚠️ Usage Warning',
              message,
              threshold === 100 ? 'critical' : 'high',
              JSON.stringify({
                usage_percentage: usagePercentage,
                consumed: monthlyRecord.consumed_kwh,
                limit: monthlyRecord.allocated_kwh,
                excess: monthlyRecord.excess_amount,
              }),
            ]
          );

          console.log(`✅ Notification sent to user ${userId}: ${threshold}% usage`);
        }
      }

      // Update notification_sent flag
      await db.query(
        `UPDATE monthly_usage 
         SET notification_sent = true 
         WHERE user_id = $1 AND month_year = $2`,
        [userId, monthlyRecord.month_year]
      );
    } catch (error) {
      console.error('❌ Error sending exceeded notification:', error);
    }
  }

  /**
   * Calculate and preserve carryover for next month
   */
  static async processMonthlyCarryover(userId, monthYear) {
    try {
      const monthlyRecord = await this.getOrCreateMonthlyUsage(userId, monthYear);

      // If user hasn't exceeded, calculate carryover
      if (!monthlyRecord.exceeded) {
        const carryoverToNext = monthlyRecord.remaining_kwh * 0.5; // Save 50% of unused

        await db.query(
          `UPDATE monthly_usage
           SET carryover_to_next = $1
           WHERE user_id = $2 AND month_year = $3`,
          [carryoverToNext, userId, monthYear]
        );

        console.log(
          `✅ Carryover calculated for user ${userId}: ${carryoverToNext.toFixed(2)} kWh`
        );

        return carryoverToNext;
      }

      return 0;
    } catch (error) {
      console.error('❌ Error processing carryover:', error);
      throw error;
    }
  }

  /**
   * Get monthly usage summary
   */
  static async getMonthlyUsageSummary(userId, monthYear = null) {
    if (!monthYear) {
      monthYear = moment().format('YYYY-MM');
    }

    try {
      const monthlyRecord = await this.getOrCreateMonthlyUsage(userId, monthYear);

      const alertsResult = await db.query(
        `SELECT * FROM usage_alerts 
         WHERE user_id = $1 
         ORDER BY created_at DESC 
         LIMIT 5`,
        [userId]
      );

      return {
        month: monthYear,
        allocated: monthlyRecord.allocated_kwh,
        consumed: monthlyRecord.consumed_kwh,
        remaining: monthlyRecord.remaining_kwh,
        carryoverFromPrevious: monthlyRecord.carryover_from_previous,
        carryoverToNext: monthlyRecord.carryover_to_next,
        exceeded: monthlyRecord.exceeded,
        excessAmount: monthlyRecord.excess_amount,
        usagePercentage: (monthlyRecord.consumed_kwh / monthlyRecord.allocated_kwh) * 100,
        recentAlerts: alertsResult.rows,
      };
    } catch (error) {
      console.error('❌ Error getting monthly summary:', error);
      throw error;
    }
  }

  /**
   * Set or update monthly limit
   */
  static async setMonthlyLimit(userId, limitKwh) {
    try {
      const result = await db.query(
        `INSERT INTO monthly_limits (user_id, monthly_limit_kwh)
         VALUES ($1, $2)
         ON CONFLICT (user_id) 
         DO UPDATE SET monthly_limit_kwh = $2, updated_at = NOW()
         RETURNING *`,
        [userId, limitKwh]
      );

      console.log(`✅ Monthly limit set for user ${userId}: ${limitKwh} kWh`);
      return result.rows[0];
    } catch (error) {
      console.error('❌ Error setting monthly limit:', error);
      throw error;
    }
  }

  /**
   * Get monthly limit
   */
  static async getMonthlyLimit(userId) {
    try {
      const result = await db.query(
        `SELECT monthly_limit_kwh FROM monthly_limits WHERE user_id = $1`,
        [userId]
      );

      return result.rows[0]?.monthly_limit_kwh || 300;
    } catch (error) {
      console.error('❌ Error getting monthly limit:', error);
      return 300; // Default limit
    }
  }
}

module.exports = MonthlyUsageService;
