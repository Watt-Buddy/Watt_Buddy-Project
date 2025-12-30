// 🧠 FEATURE 4: ML Prediction Service
const db = require('../db');
const { spawn } = require('child_process');
const path = require('path');

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

  /**
   * Detect whether the _latest_ reading is anomalous compared to recent history.
   * Uses a simple Z-score model over the last N readings (statistical ML).
   */
  static async detectLatestAnomaly(userId, options = {}) {
    try {
      if (!userId || userId === 'null' || userId === 'undefined') {
        return { isAnomaly: false };
      }

      const windowSize = options.windowSize || 100;
      const lag = options.lag || 5;

      const result = await db.query(
        `SELECT power_consumption, recorded_at
         FROM energy_readings
         WHERE user_id = $1
         ORDER BY recorded_at DESC
         LIMIT $2`,
        [userId, windowSize]
      );

      if (result.rows.length < 10) {
        // Not enough history to say anything meaningful
        return { isAnomaly: false, reason: 'insufficient_history' };
      }

      // Oldest → newest
      const rowsAsc = [...result.rows].reverse();
      const powers = rowsAsc.map(r => Number(r.power_consumption) || 0);
      const rfResult = await this.runRandomForestLatestAnomaly(userId, powers, {
        lag,
        n_estimators: options.nEstimators || 200,
      });

      return {
        isAnomaly: Boolean(rfResult.isAnomaly),
        latestPower: Number(rfResult.latestPower ?? powers[powers.length - 1] ?? 0),
        mean: Number(rfResult.meanPower ?? 0),
        stdDev: Number(rfResult.stdPower ?? 0),
        zScore: Number(rfResult.residualZScore ?? 0),
        predictedPower: Number(rfResult.predictedPower ?? 0),
        residual: Number(rfResult.residual ?? 0),
        thresholdPower: Number(rfResult.powerThreshold ?? rfResult.residualThreshold ?? 0),
        model: rfResult.model || 'RandomForestRegressor',
        timestamp: rowsAsc[rowsAsc.length - 1].recorded_at,
      };
    } catch (error) {
      console.error('❌ Error in detectLatestAnomaly (RF), using fallback:', error);
      return this.detectLatestAnomalyZScoreFallback(userId, options);
    }
  }

  static async runRandomForestLatestAnomaly(userId, powers, options = {}) {
    return new Promise((resolve, reject) => {
      const pythonProcess = spawn('python', [
        path.join(__dirname, '../../wattbudyy-ml/ml_engine.py'),
      ]);

      let output = '';
      let errorOutput = '';

      const payload = {
        user_id: String(userId),
        action: 'detect_latest_rf',
        power_data: powers,
        lag: options.lag || 5,
        n_estimators: options.n_estimators || 200,
      };

      pythonProcess.stdin.write(JSON.stringify(payload));
      pythonProcess.stdin.end();

      pythonProcess.stdout.on('data', (data) => {
        output += data.toString();
      });

      pythonProcess.stderr.on('data', (data) => {
        errorOutput += data.toString();
      });

      pythonProcess.on('close', (code) => {
        if (code !== 0) {
          reject(new Error(errorOutput || 'Random Forest ML engine failed'));
          return;
        }

        try {
          const parsed = JSON.parse(output);
          if (parsed.error) {
            reject(new Error(parsed.error));
            return;
          }
          resolve(parsed);
        } catch (parseError) {
          reject(new Error(`Failed to parse Random Forest result: ${parseError.message}`));
        }
      });

      setTimeout(() => {
        pythonProcess.kill();
        reject(new Error('Random Forest ML engine timeout'));
      }, 15000);
    });
  }

  static async detectLatestAnomalyZScoreFallback(userId, options = {}) {
    try {
      const windowSize = options.windowSize || 100;
      const zThreshold = options.zThreshold || 2.5;

      const result = await db.query(
        `SELECT power_consumption, recorded_at
         FROM energy_readings
         WHERE user_id = $1
         ORDER BY recorded_at DESC
         LIMIT $2`,
        [userId, windowSize]
      );

      if (result.rows.length < 10) {
        return { isAnomaly: false, reason: 'insufficient_history' };
      }

      const rowsAsc = [...result.rows].reverse();
      const powers = rowsAsc.map(r => Number(r.power_consumption) || 0);

      const latestPower = powers[powers.length - 1];
      const history = powers.slice(0, -1);
      const mean = history.reduce((sum, v) => sum + v, 0) / history.length;
      const variance = history.reduce((sum, v) => sum + Math.pow(v - mean, 2), 0) / history.length;
      const stdDev = Math.sqrt(variance);

      if (!isFinite(stdDev) || stdDev < 1e-3) {
        return {
          isAnomaly: false,
          latestPower,
          mean,
          stdDev,
          reason: 'low_variance',
          model: 'zscore_fallback',
        };
      }

      const zScore = Math.abs(latestPower - mean) / stdDev;
      const isAnomaly = zScore >= zThreshold;

      return {
        isAnomaly,
        latestPower,
        mean,
        stdDev,
        zScore,
        thresholdPower: mean + (zThreshold * stdDev),
        model: 'zscore_fallback',
        timestamp: rowsAsc[rowsAsc.length - 1].recorded_at,
      };
    } catch (error) {
      return { isAnomaly: false, error: error.message, model: 'zscore_fallback' };
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
