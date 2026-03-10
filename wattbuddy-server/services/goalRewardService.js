const pool = require('../db');

const POINT_RULES = {
  daily: 10,
  weekly: 30,
  monthly: 100,
};

class GoalRewardService {
  static isGoalAchieved(actualUsageKwh, goalLimitKwh) {
    return Number(actualUsageKwh) <= Number(goalLimitKwh);
  }

  static async ensureSchema() {
    await pool.query(`
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS total_points INT NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS reward_balance NUMERIC(10,2) NOT NULL DEFAULT 0
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS user_points (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        points_earned INT NOT NULL,
        period_type VARCHAR(20) NOT NULL,
        goal_limit_kwh NUMERIC(10,3) NOT NULL,
        actual_usage_kwh NUMERIC(10,3) NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_user_points_user_created
      ON user_points(user_id, created_at DESC)
    `);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS rewards (
        id SERIAL PRIMARY KEY,
        points_required INT NOT NULL UNIQUE,
        reward_value NUMERIC(10,2) NOT NULL
      )
    `);

    await pool.query(`
      INSERT INTO rewards (points_required, reward_value)
      VALUES (50, 20), (100, 50), (200, 100)
      ON CONFLICT (points_required) DO NOTHING
    `);

    // Keep redemption history separate from existing user_rewards profile table.
    await pool.query(`
      CREATE TABLE IF NOT EXISTS user_reward_redemptions (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        reward_id INT NOT NULL REFERENCES rewards(id) ON DELETE CASCADE,
        redeemed_at TIMESTAMP NOT NULL DEFAULT NOW()
      )
    `);

    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_user_reward_redemptions_user_redeemed
      ON user_reward_redemptions(user_id, redeemed_at DESC)
    `);
  }

  static async evaluateAndAward({ userId, periodType, goalLimitKwh, actualUsageKwh }) {
    if (!POINT_RULES[periodType]) {
      throw new Error('periodType must be one of: daily, weekly, monthly');
    }

    const achieved = this.isGoalAchieved(actualUsageKwh, goalLimitKwh);
    const points = achieved ? POINT_RULES[periodType] : 0;

    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      if (points > 0) {
        await client.query(
          `INSERT INTO user_points
            (user_id, points_earned, period_type, goal_limit_kwh, actual_usage_kwh)
           VALUES ($1, $2, $3, $4, $5)`,
          [userId, points, periodType, goalLimitKwh, actualUsageKwh]
        );

        await client.query(
          `UPDATE users
           SET total_points = total_points + $1
           WHERE id = $2`,
          [points, userId]
        );
      }

      const rewardsRes = await client.query(
        `SELECT id, points_required, reward_value
         FROM rewards
         WHERE points_required <= (SELECT total_points FROM users WHERE id = $1)
         ORDER BY points_required ASC`,
        [userId]
      );

      await client.query('COMMIT');

      return {
        achieved,
        pointsEarned: points,
        totalQualifiedRewards: rewardsRes.rows.length,
        qualifiedRewards: rewardsRes.rows,
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  static async getRewardStatus(userId) {
    const statusRes = await pool.query(
      `WITH u AS (
         SELECT id, total_points, reward_balance
         FROM users
         WHERE id = $1
       )
       SELECT
         u.total_points,
         u.reward_balance,
         COALESCE((
           SELECT json_agg(r ORDER BY r.points_required)
           FROM (
             SELECT id, points_required, reward_value
             FROM rewards
             WHERE points_required <= u.total_points
           ) r
         ), '[]'::json) AS available_rewards,
         (
           SELECT row_to_json(nr)
           FROM (
             SELECT id, points_required, reward_value,
                    (points_required - u.total_points) AS points_to_unlock
             FROM rewards
             WHERE points_required > u.total_points
             ORDER BY points_required ASC
             LIMIT 1
           ) nr
         ) AS next_reward
       FROM u`,
      [userId]
    );

    if (statusRes.rowCount === 0) {
      throw new Error('User not found');
    }

    return statusRes.rows[0];
  }

  static async redeemReward(userId, rewardId) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const rewardRes = await client.query(
        `SELECT id, points_required, reward_value
         FROM rewards
         WHERE id = $1`,
        [rewardId]
      );

      if (rewardRes.rowCount === 0) {
        throw new Error('Reward not found');
      }

      const reward = rewardRes.rows[0];

      const userRes = await client.query(
        `SELECT total_points
         FROM users
         WHERE id = $1
         FOR UPDATE`,
        [userId]
      );

      if (userRes.rowCount === 0) {
        throw new Error('User not found');
      }

      const totalPoints = Number(userRes.rows[0].total_points || 0);
      if (totalPoints < Number(reward.points_required)) {
        throw new Error('Insufficient points for this reward');
      }

      await client.query(
        `UPDATE users
         SET total_points = total_points - $1,
             reward_balance = reward_balance + $2
         WHERE id = $3`,
        [reward.points_required, reward.reward_value, userId]
      );

      await client.query(
        `INSERT INTO user_reward_redemptions (user_id, reward_id, redeemed_at)
         VALUES ($1, $2, NOW())`,
        [userId, rewardId]
      );

      await client.query('COMMIT');

      return {
        message: 'Reward redeemed successfully',
        pointsSpent: Number(reward.points_required),
        rewardValueAdded: Number(reward.reward_value),
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  static async applyRewardToBill(userId, originalBill) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');

      const userRes = await client.query(
        `SELECT reward_balance
         FROM users
         WHERE id = $1
         FOR UPDATE`,
        [userId]
      );

      if (userRes.rowCount === 0) {
        throw new Error('User not found');
      }

      const bill = Number(originalBill);
      const rewardBalance = Number(userRes.rows[0].reward_balance || 0);
      const rewardValue = Math.min(rewardBalance, bill);
      const finalBill = Math.max(bill - rewardValue, 0);

      await client.query(
        `UPDATE users
         SET reward_balance = reward_balance - $1
         WHERE id = $2`,
        [rewardValue, userId]
      );

      await client.query('COMMIT');

      return {
        originalBill: bill,
        rewardValue,
        finalBill,
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  static async getDashboardData({ userId, energyGoalKwh, currentUsageKwh }) {
    const goalStatus = this.isGoalAchieved(currentUsageKwh, energyGoalKwh)
      ? 'Achieved'
      : 'Not Achieved';

    const pointsTodayRes = await pool.query(
      `SELECT COALESCE(SUM(points_earned), 0) AS points_earned
       FROM user_points
       WHERE user_id = $1
         AND created_at::date = CURRENT_DATE`,
      [userId]
    );

    const status = await this.getRewardStatus(userId);

    return {
      energyGoal: Number(energyGoalKwh),
      currentEnergyUsage: Number(currentUsageKwh),
      goalStatus,
      pointsEarned: Number(pointsTodayRes.rows[0].points_earned || 0),
      totalPoints: Number(status.total_points || 0),
      availableRewards: status.available_rewards || [],
      progressToNextReward: status.next_reward || null,
      rewardBalance: Number(status.reward_balance || 0),
    };
  }
}

module.exports = GoalRewardService;
