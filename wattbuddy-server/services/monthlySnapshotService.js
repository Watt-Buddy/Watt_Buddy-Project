const pool = require('../db');
const moment = require('moment');

/**
 * Monthly Snapshot Service
 * Manages monthly energy meter snapshots for accurate billing
 */
class MonthlySnapshotService {
  
  /**
   * Get or create snapshot for a specific month
   * @param {number} userId - User ID
   * @param {string} snapshotDate - Date in YYYY-MM-DD format (typically 1st of month)
   * @returns {Promise<number>} Energy at snapshot
   */
  static async getOrCreateSnapshot(userId, snapshotDate) {
    try {
      const result = await pool.query(
        'SELECT get_or_create_month_snapshot($1::integer, $2::date) as energy',
        [userId, snapshotDate]
      );
      return parseFloat(result.rows[0]?.energy || 0);
    } catch (error) {
      console.error('❌ Error getting/creating snapshot:', error);
      throw error;
    }
  }

  /**
   * Get current total cumulative energy for user
   * @param {number} userId - User ID
   * @returns {Promise<number>} Current total energy in kWh
   */
  static async getCurrentTotalEnergy(userId) {
    try {
      const result = await pool.query(
        `SELECT COALESCE(MAX(energy_consumed), 0) AS total_energy
         FROM "EnergyReadings"
         WHERE user_id = $1::text`,
        [userId]
      );
      return parseFloat(result.rows[0]?.total_energy || 0);
    } catch (error) {
      console.error('❌ Error getting current total energy:', error);
      throw error;
    }
  }

  /**
   * Calculate current month usage using snapshot method
   * @param {number} userId - User ID
   * @returns {Promise<number>} This month's usage in kWh
   */
  static async getCurrentMonthUsage(userId) {
    try {
      const currentTotal = await this.getCurrentTotalEnergy(userId);
      const monthStart = moment().startOf('month').format('YYYY-MM-DD');
      const snapshotEnergy = await this.getOrCreateSnapshot(userId, monthStart);
      
      const usage = Math.max(0, currentTotal - snapshotEnergy);
      
      console.log(`📊 [Snapshot Method] User ${userId}: current=${currentTotal.toFixed(3)}kWh, snapshot=${snapshotEnergy.toFixed(3)}kWh, usage=${usage.toFixed(3)}kWh`);
      
      return usage;
    } catch (error) {
      console.error('❌ Error calculating current month usage:', error);
      throw error;
    }
  }

  /**
   * Get usage for a specific past month
   * @param {number} userId - User ID
   * @param {number} year - Year (e.g., 2026)
   * @param {number} month - Month (1-12)
   * @returns {Promise<number>} Month's usage in kWh
   */
  static async getMonthUsage(userId, year, month) {
    try {
      const monthStart = moment({ year, month: month - 1, day: 1 }).format('YYYY-MM-DD');
      const nextMonthStart = moment({ year, month: month - 1, day: 1 }).add(1, 'month').format('YYYY-MM-DD');
      
      // Get snapshots at start of this month and next month
      const startSnapshot = await this.getOrCreateSnapshot(userId, monthStart);
      const endSnapshot = await this.getOrCreateSnapshot(userId, nextMonthStart);
      
      const usage = Math.max(0, endSnapshot - startSnapshot);
      
      return usage;
    } catch (error) {
      console.error(`❌ Error getting month usage for ${year}-${month}:`, error);
      throw error;
    }
  }

  /**
   * Create snapshots for current month (run at month start)
   * @param {number} userId - User ID (optional, creates for all users if not provided)
   */
  static async createMonthlySnapshots(userId = null) {
    try {
      const monthStart = moment().startOf('month').format('YYYY-MM-DD');
      
      if (userId) {
        // Create for specific user
        const energy = await this.getOrCreateSnapshot(userId, monthStart);
        console.log(`✅ Created snapshot for user ${userId}: ${energy.toFixed(3)} kWh on ${monthStart}`);
        return { userId, energy, date: monthStart };
      }
      
      // Create for all users with data
      const usersResult = await pool.query(`
        SELECT DISTINCT user_id 
        FROM "EnergyReadings"
      `);
      
      const snapshots = [];
      for (const row of usersResult.rows) {
        const uid = parseInt(row.user_id);
        const energy = await this.getOrCreateSnapshot(uid, monthStart);
        snapshots.push({ userId: uid, energy, date: monthStart });
        console.log(`✅ Created snapshot for user ${uid}: ${energy.toFixed(3)} kWh`);
      }
      
      console.log(`📸 Created ${snapshots.length} monthly snapshots for ${monthStart}`);
      return snapshots;
    } catch (error) {
      console.error('❌ Error creating monthly snapshots:', error);
      throw error;
    }
  }

  /**
   * Initialize schema - ensure table and function exist
   */
  static async ensureSchema() {
    try {
      const fs = require('fs');
      const path = require('path');
      const migrationPath = path.join(__dirname, '..', 'monthly_snapshot_migration.sql');
      
      if (fs.existsSync(migrationPath)) {
        const sql = fs.readFileSync(migrationPath, 'utf8');
        await pool.query(sql);
        console.log('✅ Monthly snapshot schema initialized');
      }
    } catch (error) {
      console.error('❌ Error initializing snapshot schema:', error);
      throw error;
    }
  }

  /**
   * Get all snapshots for a user (for debugging/admin)
   */
  static async getUserSnapshots(userId, limit = 12) {
    try {
      const result = await pool.query(
        `SELECT 
           snapshot_date,
           energy_at_snapshot,
           created_at,
           to_char(snapshot_date, 'Mon YYYY') as period
         FROM monthly_snapshots
         WHERE user_id = $1
         ORDER BY snapshot_date DESC
         LIMIT $2`,
        [userId, limit]
      );
      return result.rows;
    } catch (error) {
      console.error('❌ Error getting user snapshots:', error);
      throw error;
    }
  }
}

module.exports = MonthlySnapshotService;
