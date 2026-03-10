const pool = require('../db');
const moment = require('moment');

/**
 * Goal Tracking Service
 * Handles daily/monthly energy consumption goals with carry-forward logic
 */
class GoalTrackingService {
  
  /**
   * Set or update user's energy goals
   * 
   * @param {number} userId - User ID
   * @param {Object} goals - { dailyLimitKwh, monthlyLimitKwh, carryForwardEnabled }
   * @returns {Object} Updated goal settings
   */
  static async setUserGoals(userId, goals) {
    const { dailyLimitKwh, monthlyLimitKwh, carryForwardEnabled } = goals;
    
    try {
      const query = `
        INSERT INTO user_goals (user_id, daily_limit_kwh, monthly_limit_kwh, carry_forward_enabled, last_reset_date)
        VALUES ($1, $2, $3, $4, CURRENT_DATE)
        ON CONFLICT (user_id) 
        DO UPDATE SET 
          daily_limit_kwh = COALESCE($2, user_goals.daily_limit_kwh),
          monthly_limit_kwh = COALESCE($3, user_goals.monthly_limit_kwh),
          carry_forward_enabled = COALESCE($4, user_goals.carry_forward_enabled),
          updated_at = NOW()
        RETURNING *;
      `;
      
      const result = await pool.query(query, [
        userId,
        dailyLimitKwh,
        monthlyLimitKwh,
        carryForwardEnabled
      ]);
      
      console.log(`✅ Goals set for user ${userId}:`, result.rows[0]);
      return result.rows[0];
    } catch (error) {
      console.error('❌ Error setting user goals:', error);
      throw error;
    }
  }

  /**
   * Get user's current goal settings
   * 
   * @param {number} userId - User ID
   * @returns {Object} Goal settings or default values
   */
  static async getUserGoals(userId) {
    try {
      const query = `SELECT * FROM user_goals WHERE user_id = $1`;
      const result = await pool.query(query, [userId]);
      
      if (result.rows.length > 0) {
        return result.rows[0];
      }
      
      // Return defaults if not set
      return {
        user_id: userId,
        daily_limit_kwh: 10.0,
        monthly_limit_kwh: 300.0,
        carry_forward_enabled: true,
        carried_over_kwh: 0,
        last_reset_date: moment().format('YYYY-MM-DD')
      };
    } catch (error) {
      console.error('❌ Error getting user goals:', error);
      throw error;
    }
  }

  /**
   * Check if daily reset is needed and perform carry-forward calculation
   * 
   * @param {number} userId - User ID
   * @returns {Object} Reset status and new carry-forward amount
   */
  static async checkAndResetDaily(userId) {
    try {
      const goals = await this.getUserGoals(userId);
      const today = moment().format('YYYY-MM-DD');
      const lastResetDate = moment(goals.last_reset_date).format('YYYY-MM-DD');
      
      // Check if reset is needed (new day)
      if (lastResetDate === today) {
        return { resetNeeded: false, goals };
      }
      
      console.log(`🔄 Daily reset needed for user ${userId}. Last reset: ${lastResetDate}, Today: ${today}`);
      
      // Get yesterday's usage
      const yesterdayUsage = await this.getDailyUsage(userId, lastResetDate);
      const yesterdayKwh = yesterdayUsage?.total_kwh || 0;
      
      // Calculate carry-forward amount
      let newCarryOver = 0;
      if (goals.carry_forward_enabled) {
        const availableYesterday = goals.daily_limit_kwh + goals.carried_over_kwh;
        const remaining = availableYesterday - yesterdayKwh;
        
        if (remaining > 0) {
          newCarryOver = remaining;
          console.log(`✅ Carrying forward ${newCarryOver.toFixed(3)} kWh from ${lastResetDate}`);
        } else {
          console.log(`⚠️ No carry-forward: exceeded daily limit by ${Math.abs(remaining).toFixed(3)} kWh`);
        }
      }
      
      // Update goals with new carry-forward amount
      const updateQuery = `
        UPDATE user_goals 
        SET carried_over_kwh = $1,
            last_reset_date = $2,
            updated_at = NOW()
        WHERE user_id = $3
        RETURNING *;
      `;
      
      const result = await pool.query(updateQuery, [newCarryOver, today, userId]);
      
      // Record in tracking history
      await this.recordGoalTracking(userId, lastResetDate, yesterdayKwh, goals.daily_limit_kwh, goals.carried_over_kwh);
      
      return {
        resetNeeded: true,
        previousDate: lastResetDate,
        previousUsage: yesterdayKwh,
        carriedOver: newCarryOver,
        goals: result.rows[0]
      };
    } catch (error) {
      console.error('❌ Error in daily reset:', error);
      throw error;
    }
  }

  /**
   * Get current day's energy usage progress vs goals
   * 
   * @param {number} userId - User ID
   * @returns {Object} Usage stats with goal progress
   */
  static async getCurrentProgress(userId) {
    try {
      // Ensure daily reset has been performed
      await this.checkAndResetDaily(userId);
      
      const goals = await this.getUserGoals(userId);
      const today = moment().format('YYYY-MM-DD');
      
      // Get today's usage so far
      const todayUsage = await this.getDailyUsage(userId, today);
      const currentUsageKwh = Number(todayUsage?.total_kwh ?? 0);

      // Normalize DB numeric values to JS numbers before math/toFixed operations.
      const dailyLimitKwh = Number(goals.daily_limit_kwh ?? 0);
      const carriedOverKwh = Number(goals.carried_over_kwh ?? 0);
      const monthlyLimitKwh = Number(goals.monthly_limit_kwh ?? 0);

      // Calculate available limit (daily + carried over)
      const totalAvailableKwh = dailyLimitKwh + carriedOverKwh;
      const remainingKwh = totalAvailableKwh - currentUsageKwh;
      const percentageUsed =
          totalAvailableKwh > 0 ? (currentUsageKwh / totalAvailableKwh) * 100 : 0;
      const exceeded = remainingKwh < 0;

      // Get monthly progress
      const monthStart = moment().startOf('month').format('YYYY-MM-DD');
      const monthlyUsage = await this.getMonthlyUsage(userId, monthStart);
      const monthlyUsageKwh = Number(monthlyUsage?.total_kwh ?? 0);
      const monthlyRemainingKwh = monthlyLimitKwh - monthlyUsageKwh;
      const monthlyPercentageUsed =
          monthlyLimitKwh > 0 ? (monthlyUsageKwh / monthlyLimitKwh) * 100 : 0;
      const monthlyExceeded = monthlyRemainingKwh < 0;
      
      return {
        date: today,
        daily: {
          currentUsage: parseFloat(currentUsageKwh.toFixed(3)),
          dailyLimit: parseFloat(dailyLimitKwh.toFixed(3)),
          carriedOver: parseFloat(carriedOverKwh.toFixed(3)),
          totalAvailable: parseFloat(totalAvailableKwh.toFixed(3)),
          remaining: parseFloat(remainingKwh.toFixed(3)),
          percentageUsed: parseFloat(percentageUsed.toFixed(2)),
          exceeded: exceeded,
          status: exceeded ? 'exceeded' : (percentageUsed > 80 ? 'warning' : 'good')
        },
        monthly: {
          currentUsage: parseFloat(monthlyUsageKwh.toFixed(3)),
          monthlyLimit: parseFloat(monthlyLimitKwh.toFixed(3)),
          remaining: parseFloat(monthlyRemainingKwh.toFixed(3)),
          percentageUsed: parseFloat(monthlyPercentageUsed.toFixed(2)),
          exceeded: monthlyExceeded,
          status: monthlyExceeded ? 'exceeded' : (monthlyPercentageUsed > 80 ? 'warning' : 'good')
        },
        carryForwardEnabled: goals.carry_forward_enabled
      };
    } catch (error) {
      console.error('❌ Error getting current progress:', error);
      throw error;
    }
  }

  /**
   * Get daily usage from daily_usage table
   * 
   * @param {number} userId - User ID
   * @param {string} date - Date in YYYY-MM-DD format
   * @returns {Object} Daily usage stats
   */
  static async getDailyUsage(userId, date) {
    try {
      const query = `
        SELECT * FROM daily_usage 
        WHERE user_id = $1 AND usage_date = $2
      `;
      const result = await pool.query(query, [userId, date]);
      return result.rows[0] || null;
    } catch (error) {
      console.error('❌ Error getting daily usage:', error);
      throw error;
    }
  }

  /**
   * Get monthly usage total
   * 
   * @param {number} userId - User ID
   * @param {string} monthStart - Month start date in YYYY-MM-DD format
   * @returns {Object} Monthly usage total
   */
  static async getMonthlyUsage(userId, monthStart) {
    try {
      const query = `
        SELECT 
          COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) as total_kwh,
          COALESCE(AVG(power), 0) as avg_power,
          COALESCE(MAX(power), 0) as peak_power
        FROM "EnergyReadings"
        WHERE user_id = $1::text
          AND timestamp >= $2::date
          AND timestamp < $2::date + INTERVAL '1 month'
      `;
      const result = await pool.query(query, [userId, monthStart]);
      return result.rows[0] || { total_kwh: 0, avg_power: 0, peak_power: 0 };
    } catch (error) {
      console.error('❌ Error getting monthly usage:', error);
      throw error;
    }
  }

  /**
   * Record goal tracking history
   * 
   * @param {number} userId - User ID
   * @param {string} date - Tracking date
   * @param {number} dailyUsage - Daily usage in kWh
   * @param {number} dailyLimit - Daily limit in kWh
   * @param {number} carriedOver - Carried over amount in kWh
   */
  static async recordGoalTracking(userId, date, dailyUsage, dailyLimit, carriedOver) {
    try {
      const totalAvailable = dailyLimit + carriedOver;
      const remaining = totalAvailable - dailyUsage;
      const exceeded = remaining < 0;
      
      const query = `
        INSERT INTO goal_tracking (
          user_id, tracking_date, daily_usage_kwh, daily_limit_kwh, 
          carried_over_kwh, total_available_kwh, remaining_kwh, exceeded
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (user_id, tracking_date) 
        DO UPDATE SET 
          daily_usage_kwh = $3,
          daily_limit_kwh = $4,
          carried_over_kwh = $5,
          total_available_kwh = $6,
          remaining_kwh = $7,
          exceeded = $8,
          created_at = NOW()
      `;
      
      await pool.query(query, [
        userId, date, dailyUsage, dailyLimit, 
        carriedOver, totalAvailable, remaining, exceeded
      ]);
      
      console.log(`📝 Goal tracking recorded for user ${userId} on ${date}`);
    } catch (error) {
      console.error('❌ Error recording goal tracking:', error);
      // Don't throw - this is optional tracking
    }
  }

  /**
   * Get goal tracking history
   * 
   * @param {number} userId - User ID
   * @param {number} days - Number of days to retrieve (default: 30)
   * @returns {Array} Goal tracking history
   */
  static async getGoalHistory(userId, days = 30) {
    try {
      const query = `
        SELECT * FROM goal_tracking 
        WHERE user_id = $1 
          AND tracking_date >= CURRENT_DATE - INTERVAL '${days} days'
        ORDER BY tracking_date DESC
      `;
      const result = await pool.query(query, [userId]);
      return result.rows;
    } catch (error) {
      console.error('❌ Error getting goal history:', error);
      throw error;
    }
  }
}

module.exports = GoalTrackingService;
