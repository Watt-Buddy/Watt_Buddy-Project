const pool = require('../db');
const moment = require('moment');

/**
 * Reward System Service
 * Handles points, achievements, streaks, and tiers for energy-saving users
 */
class RewardSystemService {
  
  // Points configuration
  static POINTS_CONFIG = {
    underLimit: 10,           // Points for using less than daily limit
    efficiency50: 15,         // Points for using only 50% of limit
    efficiency30: 25,         // Points for using only 30% of limit
    streak7: 7,               // Bonus points per day in 7-day streak
    streak30: 15,             // Bonus points per day in 30-day streak
    streak100: 50,            // Bonus points per day in 100-day streak
    noCarryover: 5,           // Points for not needing carryover
    consistent: 10            // Points for consistent usage
  };

  // Tier thresholds (cumulative points)
  static TIER_THRESHOLDS = {
    'Bronze': 0,
    'Silver': 100,
    'Gold': 500,
    'Platinum': 1500
  };

  /**
   * Calculate and award points for a day's usage
   * Called after daily_usage is aggregated
   * 
   * @param {number} userId - User ID
   * @param {string} date - Date in YYYY-MM-DD format
   * @returns {Object} Points earned and reasons
   */
  static async calculateDailyPoints(userId, date) {
    try {
      const goalTracking = await pool.query(
        `SELECT daily_usage_kwh, daily_limit_kwh, exceeded 
         FROM goal_tracking WHERE user_id = $1 AND tracking_date = $2`,
        [userId, date]
      );

      if (goalTracking.rows.length === 0) {
        return { pointsEarned: 0, reasons: ['No goal tracking data'] };
      }

      const { daily_usage_kwh, daily_limit_kwh, exceeded } = goalTracking.rows[0];
      let pointsEarned = 0;
      const reasons = [];

      // If exceeded, no points
      if (exceeded) {
        reasons.push('Daily limit exceeded - 0 points');
        return await this._recordDailyPoints(userId, date, 0, reasons);
      }

      // Base points for staying under limit
      pointsEarned += this.POINTS_CONFIG.underLimit;
      reasons.push(`Under limit: +${this.POINTS_CONFIG.underLimit} points`);

      // Efficiency bonuses
      const usagePercentage = (daily_usage_kwh / daily_limit_kwh) * 100;
      
      if (usagePercentage <= 30) {
        pointsEarned += this.POINTS_CONFIG.efficiency30;
        reasons.push(`30% Efficiency bonus: +${this.POINTS_CONFIG.efficiency30} points`);
      } else if (usagePercentage <= 50) {
        pointsEarned += this.POINTS_CONFIG.efficiency50;
        reasons.push(`50% Efficiency bonus: +${this.POINTS_CONFIG.efficiency50} points`);
      }

      // Streak bonus (calculated separately)
      const streakBonus = await this._calculateStreakBonus(userId, date);
      if (streakBonus > 0) {
        pointsEarned += streakBonus;
        reasons.push(`Streak bonus: +${streakBonus} points`);
      }

      // Consistency bonus (variance in usage)
      const consistencyBonus = await this._calculateConsistencyBonus(userId, date);
      if (consistencyBonus > 0) {
        pointsEarned += consistencyBonus;
        reasons.push(`Consistency bonus: +${consistencyBonus} points`);
      }

      return await this._recordDailyPoints(userId, date, pointsEarned, reasons);
    } catch (error) {
      console.error('❌ Error calculating daily points:', error);
      throw error;
    }
  }

  /**
   * Calculate streak bonus points
   * 
   * @private
   */
  static async _calculateStreakBonus(userId, date) {
    try {
      // Count consecutive days under limit up to and including current date
      const result = await pool.query(`
        WITH RECURSIVE streak AS (
          SELECT 
            tracking_date, 
            1 as streak_count
          FROM goal_tracking
          WHERE user_id = $1 
            AND tracking_date = $2::date
            AND NOT exceeded
          
          UNION ALL
          
          SELECT 
            gt.tracking_date,
            s.streak_count + 1
          FROM goal_tracking gt
          JOIN streak s ON gt.tracking_date = s.tracking_date - INTERVAL '1 day'
          WHERE gt.user_id = $1
            AND NOT gt.exceeded
        )
        SELECT MAX(streak_count) as streak_count FROM streak
      `, [userId, date]);

      const streakDays = result.rows[0]?.streak_count || 0;

      let bonus = 0;
      if (streakDays >= 100) {
        bonus = this.POINTS_CONFIG.streak100;
      } else if (streakDays >= 30) {
        bonus = this.POINTS_CONFIG.streak30;
      } else if (streakDays >= 7) {
        bonus = this.POINTS_CONFIG.streak7;
      }

      return bonus;
    } catch (error) {
      console.error('Error calculating streak bonus:', error);
      return 0;
    }
  }

  /**
   * Calculate consistency bonus (low variance in daily usage)
   * 
   * @private
   */
  static async _calculateConsistencyBonus(userId, date) {
    try {
      // Get last 7 days of usage
      const result = await pool.query(`
        SELECT 
          AVG(daily_usage_kwh) as avg_usage,
          STDDEV(daily_usage_kwh) as usage_stddev
        FROM goal_tracking
        WHERE user_id = $1
          AND tracking_date >= $2::date - INTERVAL '7 days'
          AND tracking_date <= $2::date
      `, [userId, date]);

      const { avg_usage, usage_stddev } = result.rows[0];
      
      // Low variance (predictable usage) = bonus points
      if (usage_stddev && usage_stddev < avg_usage * 0.1) {
        return this.POINTS_CONFIG.consistent;
      }
      return 0;
    } catch (error) {
      console.error('Error calculating consistency bonus:', error);
      return 0;
    }
  }

  /**
   * Record daily points and update total
   * 
   * @private
   */
  static async _recordDailyPoints(userId, date, points, reasons) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const prevRes = await client.query(
        `SELECT points_earned FROM daily_points WHERE user_id = $1 AND points_date = $2`,
        [userId, date]
      );
      const prevPoints = prevRes.rows.length > 0 ? Number(prevRes.rows[0].points_earned || 0) : 0;
      const delta = Number(points) - prevPoints;

      await client.query(
        `INSERT INTO daily_points (user_id, points_date, points_earned, reason)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, points_date)
         DO UPDATE SET
           points_earned = EXCLUDED.points_earned,
           reason = EXCLUDED.reason`,
        [userId, date, points, reasons.join(' | ')]
      );

      await client.query(
        `INSERT INTO user_rewards (user_id, total_points, tier)
         VALUES ($1, 0, 'Bronze')
         ON CONFLICT (user_id) DO NOTHING`,
        [userId]
      );

      await client.query(
        `UPDATE user_rewards
         SET total_points = GREATEST(0, total_points + $1),
             updated_at = NOW()
         WHERE user_id = $2`,
        [delta, userId]
      );

      await client.query('COMMIT');

      // Keep these outside the transaction to avoid long-held locks.
      await this._updateTier(userId);
      await this._checkAchievements(userId, date);

      return { pointsEarned: points, reasons, date, adjustedByDelta: delta };
    } catch (error) {
      await client.query('ROLLBACK');
      console.error('Error recording daily points:', error);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Update user tier based on total points
   * 
   * @private
   */
  static async _updateTier(userId) {
    try {
      const result = await pool.query(
        'SELECT total_points FROM user_rewards WHERE user_id = $1',
        [userId]
      );

      if (result.rows.length === 0) return;

      const totalPoints = result.rows[0].total_points;
      let newTier = 'Bronze';

      for (const [tier, threshold] of Object.entries(this.TIER_THRESHOLDS)) {
        if (totalPoints >= threshold) {
          newTier = tier;
        }
      }

      await pool.query(
        'UPDATE user_rewards SET tier = $1, updated_at = NOW() WHERE user_id = $2',
        [newTier, userId]
      );

      console.log(`✅ User ${userId} tier updated to: ${newTier}`);
    } catch (error) {
      console.error('Error updating tier:', error);
    }
  }

  /**
   * Check and unlock achievements
   * 
   * @private
   */
  static async _checkAchievements(userId, date) {
    try {
      const goalTracking = await pool.query(
        `SELECT daily_usage_kwh, daily_limit_kwh 
         FROM goal_tracking WHERE user_id = $1 AND tracking_date = $2`,
        [userId, date]
      );

      if (goalTracking.rows.length === 0) return;

      const { daily_usage_kwh, daily_limit_kwh } = goalTracking.rows[0];
      const usagePercentage = (daily_usage_kwh / daily_limit_kwh) * 100;

      // Get current streak
      const streakResult = await pool.query(`
        WITH RECURSIVE streak AS (
          SELECT 
            tracking_date, 
            1 as streak_count
          FROM goal_tracking
          WHERE user_id = $1 
            AND tracking_date = $2::date
            AND NOT exceeded
          
          UNION ALL
          
          SELECT 
            gt.tracking_date,
            s.streak_count + 1
          FROM goal_tracking gt
          JOIN streak s ON gt.tracking_date = s.tracking_date - INTERVAL '1 day'
          WHERE gt.user_id = $1
            AND NOT gt.exceeded
        )
        SELECT MAX(streak_count) as streak_count FROM streak
      `, [userId, date]);

      const streakDays = streakResult.rows[0]?.streak_count || 0;

      // Check achievements
      const achievementsToUnlock = [];

      // First day under limit
      const firstDayResult = await pool.query(
        `SELECT COUNT(*) as count FROM goal_tracking 
         WHERE user_id = $1 AND NOT exceeded`,
        [userId]
      );
      if (firstDayResult.rows[0].count === 1) {
        achievementsToUnlock.push('first_day_under');
      }

      // Streaks
      if (streakDays === 7) achievementsToUnlock.push('streak_7');
      if (streakDays === 30) achievementsToUnlock.push('streak_30');
      if (streakDays === 100) achievementsToUnlock.push('streak_100');

      // Efficiency
      if (usagePercentage <= 50) achievementsToUnlock.push('efficiency_50');
      if (usagePercentage <= 30) achievementsToUnlock.push('efficiency_30');

      // Power user (consistent)
      if (streakDays >= 14) achievementsToUnlock.push('power_user');

      // Unlock achievements
      for (const key of achievementsToUnlock) {
        await this._unlockAchievement(userId, key);
      }
    } catch (error) {
      console.error('Error checking achievements:', error);
    }
  }

  /**
   * Unlock an achievement for user
   * 
   * @private
   */
  static async _unlockAchievement(userId, achievementKey) {
    try {
      // Get achievement ID
      const achievement = await pool.query(
        'SELECT id, points_reward FROM achievements WHERE achievement_key = $1',
        [achievementKey]
      );

      if (achievement.rows.length === 0) return;

      const { id: achievementId, points_reward } = achievement.rows[0];

      // Check if already unlocked
      const existing = await pool.query(
        'SELECT id FROM user_achievements WHERE user_id = $1 AND achievement_id = $2',
        [userId, achievementId]
      );

      if (existing.rows.length > 0) return; // Already unlocked

      // Unlock achievement
      await pool.query(
        'INSERT INTO user_achievements (user_id, achievement_id) VALUES ($1, $2)',
        [userId, achievementId]
      );

      // Award achievement bonus points
      await pool.query(
        'UPDATE user_rewards SET total_points = total_points + $1 WHERE user_id = $2',
        [points_reward, userId]
      );

      // Update tier
      await this._updateTier(userId);

      console.log(`🏆 Achievement unlocked for user ${userId}: ${achievementKey} (+${points_reward} points)`);
    } catch (error) {
      console.error('Error unlocking achievement:', error);
    }
  }

  /**
   * Get user's reward profile
   * 
   * @param {number} userId - User ID
   * @returns {Object} Reward profile with points, tier, streaks
   */
  static async getUserRewards(userId) {
    try {
      // Get reward info
      const rewardResult = await pool.query(
        'SELECT * FROM user_rewards WHERE user_id = $1',
        [userId]
      );

      if (rewardResult.rows.length === 0) {
        return { user_id: userId, totalPoints: 0, tier: 'Bronze', achievements: [] };
      }

      const rewards = rewardResult.rows[0];

      // Get achievements
      const achievementResult = await pool.query(`
        SELECT 
          a.achievement_key,
          a.name,
          a.description,
          a.points_reward,
          ua.unlocked_at
        FROM user_achievements ua
        JOIN achievements a ON ua.achievement_id = a.id
        WHERE ua.user_id = $1
        ORDER BY ua.unlocked_at DESC
      `, [userId]);

      // Get current streak
      const streakResult = await pool.query(`
        WITH RECURSIVE streak AS (
          SELECT 
            tracking_date, 
            1 as streak_count
          FROM goal_tracking
          WHERE user_id = $1 
            AND tracking_date = CURRENT_DATE
            AND NOT exceeded
          
          UNION ALL
          
          SELECT 
            gt.tracking_date,
            s.streak_count + 1
          FROM goal_tracking gt
          JOIN streak s ON gt.tracking_date = s.tracking_date - INTERVAL '1 day'
          WHERE gt.user_id = $1
            AND NOT gt.exceeded
        )
        SELECT MAX(streak_count) as streak_count FROM streak
      `, [userId]);

      const currentStreak = streakResult.rows[0]?.streak_count || 0;

      return {
        user_id: userId,
        totalPoints: rewards.total_points,
        tier: rewards.tier,
        currentStreak: currentStreak,
        achievementsUnlocked: achievementResult.rows.length,
        achievements: achievementResult.rows,
        progressToNextTier: this._getProgressToNextTier(rewards.total_points, rewards.tier)
      };
    } catch (error) {
      console.error('Error getting user rewards:', error);
      throw error;
    }
  }

  /**
   * Get leaderboard (top energy savers)
   * 
   * @param {number} limit - Number of users to return (default: 10)
   * @returns {Array} Top energy savers
   */
  static async getLeaderboard(limit = 10) {
    try {
      const result = await pool.query(`
        SELECT 
          ur.user_id,
          u.username,
          ur.total_points,
          ur.tier,
          ur.streak_days as current_streak,
          ur.achievements_unlocked,
          ROW_NUMBER() OVER (ORDER BY ur.total_points DESC) as rank
        FROM user_rewards ur
        JOIN users u ON ur.user_id = u.id
        ORDER BY ur.total_points DESC
        LIMIT $1
      `, [limit]);

      return result.rows;
    } catch (error) {
      console.error('Error getting leaderboard:', error);
      throw error;
    }
  }

  /**
   * Get points history for a user
   * 
   * @param {number} userId - User ID
   * @param {number} days - Number of days to retrieve
   * @returns {Array} Daily points history
   */
  static async getPointsHistory(userId, days = 30) {
    try {
      const result = await pool.query(`
        SELECT * FROM daily_points 
        WHERE user_id = $1 
          AND points_date >= CURRENT_DATE - INTERVAL '${days} days'
        ORDER BY points_date DESC
      `, [userId]);

      return result.rows;
    } catch (error) {
      console.error('Error getting points history:', error);
      throw error;
    }
  }

  /**
   * Helper: Get progress to next tier
   * 
   * @private
   */
  static _getProgressToNextTier(totalPoints, currentTier) {
    const tiers = ['Bronze', 'Silver', 'Gold', 'Platinum'];
    const currentIndex = tiers.indexOf(currentTier);
    
    if (currentIndex === -1 || currentIndex >= tiers.length - 1) {
      return { nextTier: null, pointsNeeded: 0, progressPercent: 100 };
    }

    const nextTier = tiers[currentIndex + 1];
    const nextThreshold = this.TIER_THRESHOLDS[nextTier];
    const pointsNeeded = nextThreshold - totalPoints;
    const progressPercent = ((totalPoints - this.TIER_THRESHOLDS[currentTier]) / 
                           (nextThreshold - this.TIER_THRESHOLDS[currentTier])) * 100;

    return {
      nextTier,
      pointsNeeded: Math.max(0, pointsNeeded),
      progressPercent: Math.min(100, progressPercent)
    };
  }

  /**
   * Get all available achievements
   * 
   * @returns {Array} All achievements with descriptions
   */
  static async getAllAchievements() {
    try {
      const result = await pool.query(`
        SELECT 
          achievement_key,
          name,
          description,
          points_reward,
          tier_requirement,
          icon
        FROM achievements
        ORDER BY points_reward
      `);

      return result.rows;
    } catch (error) {
      console.error('Error getting achievements:', error);
      throw error;
    }
  }
}

module.exports = RewardSystemService;
