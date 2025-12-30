const pool = require('../db');
const moment = require('moment');

/**
 * Daily Analytics Service
 * Handles daily usage aggregation and baseline statistics for anomaly detection
 */
class DailyAnalyticsService {
  
  /**
   * Aggregate today's energy usage from EnergyReadings into daily_usage table
   * Computes: total_kwh, avg_power, peak_power for the day
   * 
   * @param {string|number} userId - User ID
   * @param {string} usageDate - Date in YYYY-MM-DD format (defaults to today)
   */
  static async aggregateDailyUsage(userId, usageDate = null) {
    if (!usageDate) {
      usageDate = moment().format('YYYY-MM-DD');
    }

    try {
      // Compute stats for the specific day
      const aggregateQuery = `
        WITH day_stats AS (
          SELECT 
            MAX(energy_consumed) - MIN(energy_consumed) AS total_kwh,
            AVG(power) AS avg_power,
            MAX(power) AS peak_power
          FROM "EnergyReadings"
          WHERE user_id = $1::text
            AND timestamp::date = $2::date
        )
        INSERT INTO daily_usage (user_id, usage_date, total_kwh, avg_power, peak_power)
        SELECT $1::int, $2::date, 
               COALESCE(total_kwh, 0), 
               COALESCE(avg_power, 0), 
               COALESCE(peak_power, 0)
        FROM day_stats
        ON CONFLICT (user_id, usage_date) 
        DO UPDATE SET 
          total_kwh = EXCLUDED.total_kwh,
          avg_power = EXCLUDED.avg_power,
          peak_power = EXCLUDED.peak_power,
          created_at = NOW()
        RETURNING *;
      `;

      const result = await pool.query(aggregateQuery, [userId, usageDate]);
      
      if (result.rows.length > 0) {
        console.log(`📊 Daily usage aggregated for user ${userId} on ${usageDate}:`, result.rows[0]);
        return result.rows[0];
      }
      
      return null;
    } catch (error) {
      console.error('❌ Error aggregating daily usage:', error);
      throw error;
    }
  }

  /**
   * Get user's baseline statistics from historical daily usage
   * Includes a short grace period for new users (first 2 days)
   * 
   * @param {string|number} userId - User ID
   * @param {number} lookbackDays - Number of days to analyze (default: 30)
   * @returns {Object} { mean, stddev, threshold, sampleSize, isInGracePeriod, daysSinceSignup }
   */
  static async getUserBaseline(userId, lookbackDays = 30) {
    try {
      // First, check user creation date to determine if in grace period
      const userAgeQuery = `
        SELECT 
          EXTRACT(DAY FROM (NOW() - created_at)) as days_since_signup
        FROM users
        WHERE id = $1::int;
      `;
      
      const userAgeResult = await pool.query(userAgeQuery, [userId]);
      const daysSinceSignup = userAgeResult.rows[0]?.days_since_signup || 0;
      
      // Grace period: first 2 days while initial usage history is collected.
      const isInGracePeriod = daysSinceSignup < 2;

      const baselineQuery = `
        WITH daily_stats AS (
          SELECT 
            avg_power,
            usage_date
          FROM daily_usage
          WHERE user_id = $1::int
            AND usage_date >= CURRENT_DATE - INTERVAL '${lookbackDays} days'
            AND avg_power > 0  -- Exclude zero/invalid readings
          ORDER BY usage_date DESC
        )
        SELECT 
          COUNT(*) as sample_size,
          AVG(avg_power) as mean_power,
          STDDEV_POP(avg_power) as stddev_power,
          PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY avg_power) as p95_power,
          MIN(avg_power) as min_power,
          MAX(avg_power) as max_power
        FROM daily_stats;
      `;

      const result = await pool.query(baselineQuery, [userId]);
      
      if (result.rows.length === 0 || parseInt(result.rows[0].sample_size || 0) === 0) {
        // Fallback: derive baseline directly from raw EnergyReadings if daily rollups are missing.
        const readingsFallbackQuery = `
          SELECT
            COUNT(*) as sample_size,
            AVG(power) as mean_power,
            STDDEV_POP(power) as stddev_power,
            PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY power) as p95_power,
            MIN(power) as min_power,
            MAX(power) as max_power
          FROM "EnergyReadings"
          WHERE user_id = $1::text
            AND timestamp >= NOW() - INTERVAL '${lookbackDays} days'
            AND power > 0;
        `;

        const readingsResult = await pool.query(readingsFallbackQuery, [String(userId)]);
        const readingsStats = readingsResult.rows[0] || {};
        const rawSampleSize = parseInt(readingsStats.sample_size || 0);

        if (rawSampleSize > 0) {
          const mean = parseFloat(readingsStats.mean_power || 75);
          const stddev = parseFloat(readingsStats.stddev_power || 25);
          const p95 = parseFloat(readingsStats.p95_power || mean * 1.5);

          let threshold;
          if (isInGracePeriod) {
            threshold = 999999;
            console.log(`📈 User ${userId} IN GRACE PERIOD (${daysSinceSignup}d): alerts disabled while learning.`);
          } else {
            const zScoreThreshold = mean + (2 * stddev);
            threshold = Math.max(zScoreThreshold, p95, 150);
            console.log(`📈 User ${userId} fallback baseline from EnergyReadings: mean=${mean.toFixed(1)}W, stddev=${stddev.toFixed(1)}W, threshold=${threshold.toFixed(1)}W (n=${rawSampleSize} readings)`);
          }

          return {
            mean,
            stddev,
            threshold,
            sampleSize: rawSampleSize,
            p95,
            min: parseFloat(readingsStats.min_power || 0),
            max: parseFloat(readingsStats.max_power || 0),
            isDefault: false,
            source: 'energy_readings_fallback',
            isInGracePeriod,
            daysSinceSignup
          };
        }

        console.warn(`⚠️ No historical data for user ${userId}, using conservative default baseline`);
        return {
          mean: 75,
          stddev: 25,
          threshold: isInGracePeriod ? 999999 : 150,
          sampleSize: 0,
          p95: 150,
          min: 0,
          max: 0,
          isDefault: true,
          source: 'default',
          isInGracePeriod: isInGracePeriod,
          daysSinceSignup: daysSinceSignup
        };
      }

      const stats = result.rows[0];
      const mean = parseFloat(stats.mean_power || 75);
      const stddev = parseFloat(stats.stddev_power || 25);
      const p95 = parseFloat(stats.p95_power || mean * 1.5);
      const sampleSize = parseInt(stats.sample_size || 0);
      const minSampleSize = isInGracePeriod ? 999 : 1; // After grace, analyze and alert with any available history

      // During grace period: disable alerts. With limited history after grace, use conservative threshold.
      let threshold;
      if (isInGracePeriod) {
        threshold = 999999;
        console.log(`📈 User ${userId} IN GRACE PERIOD (${daysSinceSignup}d): alerts disabled, threshold=∞ (learning usage pattern)`);
      } else if (sampleSize < minSampleSize) {
        threshold = Math.max(p95, 150);
        console.log(`📈 User ${userId} limited history (n=${sampleSize}). Using conservative threshold=${threshold.toFixed(1)}W`);
      } else {
        // Dynamic threshold using Z-score approach (mean + 2*stddev for 95% confidence)
        const zScoreThreshold = mean + (2 * stddev);
        threshold = Math.max(zScoreThreshold, p95);
        console.log(`📈 User ${userId} baseline: mean=${mean.toFixed(1)}W, stddev=${stddev.toFixed(1)}W, threshold=${threshold.toFixed(1)}W (n=${sampleSize}d)`);
      }

      return {
        mean: mean,
        stddev: stddev,
        threshold: threshold,
        sampleSize: sampleSize,
        p95: p95,
        min: parseFloat(stats.min_power || 0),
        max: parseFloat(stats.max_power || 0),
        isDefault: false,
        isInGracePeriod: isInGracePeriod,
        daysSinceSignup: daysSinceSignup
      };
    } catch (error) {
      console.error('❌ Error computing user baseline:', error);
      // Return safe defaults on error (very high threshold to avoid alerts)
      return {
        mean: 75,
        stddev: 25,
        threshold: 999999,
        sampleSize: 0,
        p95: 150,
        min: 0,
        max: 0,
        isDefault: true,
        isInGracePeriod: true,
        daysSinceSignup: 0,
        error: error.message
      };
    }
  }

  /**
   * Check if current power reading is anomalous based on user's baseline
   * 
   * @param {string|number} userId - User ID
   * @param {number} currentPower - Current power reading in Watts
   * @returns {Object} { isAnomaly, severity, threshold, zScore }
   */
  static async detectPowerAnomaly(userId, currentPower) {
    try {
      const baseline = await this.getUserBaseline(userId);
      
      const isAnomaly = currentPower > baseline.threshold;
      
      // Calculate Z-score for severity assessment
      let zScore = 0;
      if (baseline.stddev > 0) {
        zScore = (currentPower - baseline.mean) / baseline.stddev;
      }

      // Severity levels:
      // 0-2 sigma: Normal
      // 2-3 sigma: Moderate
      // 3+ sigma: High
      let severity = 'normal';
      if (zScore > 3) {
        severity = 'high';
      } else if (zScore > 2) {
        severity = 'moderate';
      }

      return {
        isAnomaly,
        severity,
        threshold: baseline.threshold,
        zScore: zScore.toFixed(2),
        currentPower,
        baseline: baseline.mean,
        stddev: baseline.stddev,
        sampleSize: baseline.sampleSize
      };
    } catch (error) {
      console.error('❌ Error detecting power anomaly:', error);
      // Return safe default
      return {
        isAnomaly: false,
        severity: 'normal',
        threshold: 150,
        zScore: 0,
        currentPower,
        baseline: 75,
        stddev: 25,
        sampleSize: 0,
        error: error.message
      };
    }
  }

  /**
   * Get daily usage history for a user (for bar charts)
   * 
   * @param {string|number} userId - User ID
   * @param {number} days - Number of days to retrieve (default: 30)
   * @returns {Array} Array of {usage_date, total_kwh, avg_power, peak_power}
   */
  static async getDailyHistory(userId, days = 30) {
    try {
      const historyQuery = `
        SELECT 
          usage_date,
          total_kwh,
          avg_power,
          peak_power
        FROM daily_usage
        WHERE user_id = $1::int
          AND usage_date >= CURRENT_DATE - INTERVAL '${days} days'
        ORDER BY usage_date ASC;
      `;

      const result = await pool.query(historyQuery, [userId]);
      return result.rows;
    } catch (error) {
      console.error('❌ Error fetching daily history:', error);
      return [];
    }
  }

  /**
   * Get current month's daily usage (for month-to-date bar chart)
   * 
   * @param {string|number} userId - User ID
   * @returns {Array} Array of {day, kwh} for each day of current month
   */
  static async getCurrentMonthDailyUsage(userId) {
    try {
      const query = `
        WITH daily_data AS (
          SELECT 
            EXTRACT(DAY FROM usage_date)::int as day,
            total_kwh as kwh
          FROM daily_usage
          WHERE user_id = $1::int
            AND usage_date >= DATE_TRUNC('month', CURRENT_DATE)
            AND usage_date <= CURRENT_DATE
        )
        SELECT 
          d.day,
          COALESCE(daily_data.kwh, 0) as kwh
        FROM (SELECT generate_series(1, EXTRACT(DAY FROM CURRENT_DATE)::int) as day) d
        LEFT JOIN daily_data ON d.day = daily_data.day
        ORDER BY d.day ASC;
      `;

      const result = await pool.query(query, [userId]);
      
      // If no data in daily_usage, fall back to computing from EnergyReadings
      if (result.rows.every(row => row.kwh === 0)) {
        console.warn(`⚠️ No daily_usage data for user ${userId}, computing from EnergyReadings`);
        
        const fallbackQuery = `
          WITH daily_data AS (
            SELECT 
              EXTRACT(DAY FROM timestamp)::int as day,
              MAX(energy_consumed) - MIN(energy_consumed) as kwh
            FROM "EnergyReadings"
            WHERE user_id = $1::text
              AND timestamp >= DATE_TRUNC('month', CURRENT_DATE)
            GROUP BY day
          )
          SELECT 
            d.day,
            COALESCE(daily_data.kwh, 0) as kwh
          FROM (SELECT generate_series(1, EXTRACT(DAY FROM CURRENT_DATE)::int) as day) d
          LEFT JOIN daily_data ON d.day = daily_data.day
          ORDER BY d.day ASC;
        `;
        
        const fallbackResult = await pool.query(fallbackQuery, [userId]);
        return fallbackResult.rows;
      }

      return result.rows;
    } catch (error) {
      console.error('❌ Error fetching current month daily usage:', error);
      return [];
    }
  }

  /**
   * Initialize/backfill daily_usage table from historical EnergyReadings
   * Use this to populate daily_usage for past days if not already done
   * 
   * @param {string|number} userId - User ID
   * @param {number} daysBack - Number of days to backfill (default: 90)
   */
  static async backfillDailyUsage(userId, daysBack = 90) {
    try {
      console.log(`🔄 Backfilling daily_usage for user ${userId} (${daysBack} days)...`);
      
      const backfillQuery = `
        INSERT INTO daily_usage (user_id, usage_date, total_kwh, avg_power, peak_power)
        SELECT 
          $1::int as user_id,
          timestamp::date as usage_date,
          MAX(energy_consumed) - MIN(energy_consumed) as total_kwh,
          AVG(power) as avg_power,
          MAX(power) as peak_power
        FROM "EnergyReadings"
        WHERE user_id = $1::text
          AND timestamp >= CURRENT_DATE - INTERVAL '${daysBack} days'
        GROUP BY timestamp::date
        ON CONFLICT (user_id, usage_date) 
        DO UPDATE SET 
          total_kwh = EXCLUDED.total_kwh,
          avg_power = EXCLUDED.avg_power,
          peak_power = EXCLUDED.peak_power,
          created_at = NOW()
        RETURNING usage_date, total_kwh;
      `;

      const result = await pool.query(backfillQuery, [userId]);
      console.log(`✅ Backfilled ${result.rows.length} days of data for user ${userId}`);
      
      return result.rows;
    } catch (error) {
      console.error('❌ Error backfilling daily usage:', error);
      throw error;
    }
  }
}

module.exports = DailyAnalyticsService;
