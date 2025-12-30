// 🗄 FEATURE 2: Store ESP32 Data in PostgreSQL
const db = require('../db');
const PowerLimitService = require('./powerLimitService');

class ESP32StorageService {
  // Store ESP32 reading in database
  static async storeReading(userId, reading) {
    try {
      // Extract data from ESP32
      const {
        power,
        voltage,
        current,
        energy,
        pf,
        frequency,
        temperature,
        timestamp = new Date()
      } = reading;

      // Insert into energy_readings table
      const result = await db.query(
        `INSERT INTO energy_readings 
         (user_id, power_consumption, voltage, current, energy, power_factor, frequency, temperature, recorded_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         RETURNING *`,
        [userId, power, voltage, current, energy, pf, frequency, temperature, timestamp]
      );

      console.log(`✅ ESP32 reading stored for user ${userId}`);

      // Check power limit and send notifications
      const settings = await PowerLimitService.getPowerLimitSettings(userId);
      await PowerLimitService.checkPowerLimit(userId, power, settings.daily_power_limit);

      return result.rows[0];
    } catch (error) {
      console.error('❌ Error storing ESP32 reading:', error);
      throw error;
    }
  }

  // Get latest readings for graph/dashboard
  static async getLatestReadings(userId, limit = 100) {
    try {
      const result = await db.query(
        `SELECT * FROM energy_readings
         WHERE user_id = $1
         ORDER BY recorded_at DESC
         LIMIT $2`,
        [userId, limit]
      );

      return result.rows.reverse(); // Return oldest first for time-series
    } catch (error) {
      console.error('❌ Error fetching readings:', error);
      throw error;
    }
  }

  // Get readings for specific time range
  static async getReadingsByTimeRange(userId, startTime, endTime) {
    try {
      const result = await db.query(
        `SELECT * FROM energy_readings
         WHERE user_id = $1 AND recorded_at >= $2 AND recorded_at <= $3
         ORDER BY recorded_at ASC`,
        [userId, startTime, endTime]
      );

      return result.rows;
    } catch (error) {
      console.error('❌ Error fetching readings by time range:', error);
      throw error;
    }
  }

  // Get hourly statistics
  static async getHourlyStats(userId, date) {
    try {
      const result = await db.query(
        `SELECT 
           DATE_TRUNC('hour', recorded_at) as hour,
           AVG(power_consumption) as avg_power,
           MAX(power_consumption) as peak_power,
           MIN(power_consumption) as min_power,
           SUM(energy) as total_energy,
           COUNT(*) as reading_count
         FROM energy_readings
         WHERE user_id = $1 AND DATE(recorded_at) = $2
         GROUP BY DATE_TRUNC('hour', recorded_at)
         ORDER BY hour ASC`,
        [userId, date]
      );

      return result.rows;
    } catch (error) {
      console.error('❌ Error fetching hourly stats:', error);
      throw error;
    }
  }

  // Get daily summary
  static async getDailySummary(userId, date) {
    try {
      const result = await db.query(
        `SELECT 
           DATE(recorded_at) as date,
           AVG(power_consumption) as avg_power,
           MAX(power_consumption) as peak_power,
           MIN(power_consumption) as min_power,
           SUM(energy) as total_energy,
           AVG(voltage) as avg_voltage,
           AVG(current) as avg_current,
           AVG(power_factor) as avg_pf
         FROM energy_readings
         WHERE user_id = $1 AND DATE(recorded_at) = $2
         GROUP BY DATE(recorded_at)`,
        [userId, date]
      );

      return result.rows[0] || null;
    } catch (error) {
      console.error('❌ Error fetching daily summary:', error);
      throw error;
    }
  }
}

module.exports = ESP32StorageService;
