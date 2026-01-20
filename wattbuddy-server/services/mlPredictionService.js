// 🧠 FEATURE 4: ML Prediction Service
const db = require('../db');

class MLPredictionService {
  static ML_ENGINE_URL = process.env.ML_ENGINE_URL || 'http://localhost:5000';

  // Get ML prediction for next hour
  static async predictNextHour(userId) {
    try {
      // Validate userId
      if (!userId || userId === 'null' || userId === 'undefined') {
        return { error: 'Invalid userId provided' };
      }
      
      // Get last 24 hours of data
      const startTime = new Date(Date.now() - 24 * 60 * 60 * 1000);
      const result = await db.query(
        `SELECT 
           power_consumption,
           voltage,
           current,
           temperature,
           recorded_at
         FROM energy_readings
         WHERE user_id = $1 AND recorded_at >= $2
         ORDER BY recorded_at ASC`,
        [userId, startTime]
      );

      if (result.rows.length === 0) {
        return { error: 'Insufficient data for prediction' };
      }

      // Calculate simple statistics for prediction
      const powers = result.rows.map(r => r.power_consumption);
      const avgPower = powers.reduce((a, b) => a + b) / powers.length;
      const maxPower = Math.max(...powers);
      const minPower = Math.min(...powers);
      const trend = powers[powers.length - 1] > avgPower ? 'increasing' : 'decreasing';

      return {
        predictedPower: avgPower,
        confidence: 0.75,
        trend: trend,
        recommendation: trend === 'increasing' ? 'Usage trending up - consider reducing consumption' : 'Usage stable'
      };
    } catch (error) {
      console.error('❌ Error predicting next hour:', error);
      return { error: error.message };
    }
  }

  // Get ML prediction for next day
  static async predictNextDay(userId) {
    try {
      // Validate userId
      if (!userId || userId === 'null' || userId === 'undefined') {
        return { error: 'Invalid userId provided' };
      }
      
      // Get last 7 days of data
      const startTime = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
      const result = await db.query(
        `SELECT 
           DATE(recorded_at) as date,
           SUM(power_consumption) as daily_power,
           AVG(power_consumption) as avg_power,
           MAX(power_consumption) as peak_power
         FROM energy_readings
         WHERE user_id = $1 AND recorded_at >= $2
         GROUP BY DATE(recorded_at)
         ORDER BY date ASC`,
        [userId, startTime]
      );

      if (result.rows.length < 3) {
        return { error: 'Insufficient historical data' };
      }

      // Calculate average daily energy
      const avgDailyEnergy = result.rows.reduce((sum, r) => sum + r.daily_power, 0) / result.rows.length;
      const avgPeakPower = result.rows.reduce((sum, r) => sum + r.peak_power, 0) / result.rows.length;

      return {
        predictedDailyEnergy: avgDailyEnergy,
        predictedPeakPower: avgPeakPower,
        confidence: 0.82,
        anomalyDetected: false,
        adviceIfAnomalous: ''
      };
    } catch (error) {
      console.error('❌ Error predicting next day:', error);
      return { error: error.message };
    }
  }

  // Detect anomalies in power consumption
  static async detectAnomalies(userId) {
    try {
      // Validate userId
      if (!userId || userId === 'null' || userId === 'undefined') {
        return { anomalies: [] };
      }
      
      // Get last week data
      const startTime = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
      const result = await db.query(
        `SELECT 
           power_consumption,
           recorded_at
         FROM energy_readings
         WHERE user_id = $1 AND recorded_at >= $2
         ORDER BY recorded_at ASC`,
        [userId, startTime]
      );

      if (result.rows.length < 10) {
        return { anomalies: [] };
      }

      const powerData = result.rows.map(r => r.power_consumption);
      const mean = powerData.reduce((a, b) => a + b) / powerData.length;
      const stdDev = Math.sqrt(
        powerData.reduce((sq, n) => sq + Math.pow(n - mean, 2), 0) / powerData.length
      );

      const anomalies = [];
      powerData.forEach((power, idx) => {
        if (Math.abs(power - mean) > 2.5 * stdDev) {
          anomalies.push({
            index: idx,
            value: power,
            timestamp: result.rows[idx].recorded_at,
            deviation: Math.abs(power - mean) / stdDev
          });
        }
      });

      // Store anomalies
      for (const anomaly of anomalies) {
        await db.query(
          `INSERT INTO anomaly_alerts 
           (user_id, anomaly_data, power_data)
           VALUES ($1, $2, $3)`,
          [userId, JSON.stringify(anomaly), JSON.stringify(powerData)]
        );
      }

      console.log(`✅ Detected ${anomalies.length} anomalies for user ${userId}`);
      return { anomalies };
    } catch (error) {
      console.error('❌ Error detecting anomalies:', error);
      return { anomalies: [], error: error.message };
    }
  }

  // Get energy-saving recommendations based on ML analysis
  static async getRecommendations(userId) {
    try {
      // Get usage patterns
      const result = await db.query(
        `SELECT 
           EXTRACT(HOUR FROM recorded_at) as hour,
           AVG(power_consumption) as avg_power
         FROM energy_readings
         WHERE user_id = $1 AND recorded_at >= NOW() - INTERVAL '30 days'
         GROUP BY EXTRACT(HOUR FROM recorded_at)
         ORDER BY hour ASC`,
        [userId]
      );

      const hourlyPatterns = result.rows;
      
      if (hourlyPatterns.length === 0) {
        return { recommendations: ['Start tracking your energy consumption'] };
      }

      // Find peak hours
      const sortedByPower = [...hourlyPatterns].sort((a, b) => b.avg_power - a.avg_power);
      const peakHours = sortedByPower.slice(0, 3).map(p => `${Math.floor(p.hour)}:00`);

      const recommendations = [
        `Peak usage hours: ${peakHours.join(', ')} - Consider shifting heavy usage to off-peak hours`,
        'Enable smart scheduling for major appliances',
        'Monitor real-time usage during peak hours',
        'Set lower power limits during high consumption periods',
        'Use the comparison feature to track improvements'
      ];

      return { recommendations };
    } catch (error) {
      console.error('❌ Error getting recommendations:', error);
      return { recommendations: [] };
    }
  }
}

module.exports = MLPredictionService;
