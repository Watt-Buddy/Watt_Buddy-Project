const pool = require('../db');
const moment = require('moment');

class PatternAnalysisService {
  static async analyzeConsumptionPatterns(userId) {
    try {
      const thirtyDaysAgo = moment().subtract(30, 'days').toISOString();

      // Get 30-day power readings
      const query = `
        SELECT 
          EXTRACT(HOUR FROM timestamp) as hour_of_day,
          EXTRACT(DOW FROM timestamp) as day_of_week,
          AVG(power) as avg_power,
          STDDEV(power) as stddev_power,
          MAX(power) as max_power,
          MIN(power) as min_power,
          COUNT(*) as reading_count
        FROM "EnergyReadings"
        WHERE user_id = $1 AND timestamp > $2
        GROUP BY hour_of_day, day_of_week
      `;

      const result = await pool.query(query, [userId, thirtyDaysAgo]);

      if (result.rows.length === 0) {
        return null; // Insufficient data
      }

      const patternData = JSON.stringify(result.rows);
      await pool.query(
        `INSERT INTO user_power_patterns (user_id, pattern_data, analyzed_at)
         VALUES ($1, $2, NOW())
         ON CONFLICT (user_id) DO UPDATE SET pattern_data = $2, analyzed_at = NOW()`,
        [userId, patternData]
      );

      return result.rows;
    } catch (error) {
      console.error('❌ Pattern analysis failed:', error);
      return null;
    }
  }

  static async getExpectedPowerRange(userId, patterns) {
    try {
      if (!patterns || patterns.length === 0) {
        return null;
      }

      const now = moment();
      const currentHour = now.hour();
      const currentDOW = now.day();

      // Find matching hour/dow pattern
      const matchingPattern = patterns.find(
        p => p.hour_of_day === currentHour && p.day_of_week === currentDOW
      );

      if (!matchingPattern) {
        // Fall back to same hour across all days
        const hourPattern = patterns.filter(p => p.hour_of_day === currentHour);
        if (hourPattern.length === 0) return null;

        const avgPower = hourPattern.reduce((sum, p) => sum + p.avg_power, 0) / hourPattern.length;
        const stddev = hourPattern.reduce((sum, p) => sum + (p.stddev_power || 0), 0) / hourPattern.length;

        return {
          expectedAvg: avgPower,
          expectedStddev: stddev || 15,
          expectedRange: [avgPower - 2 * (stddev || 15), avgPower + 2 * (stddev || 15)],
          confidence: 'low', // fallback
          readingCount: hourPattern.reduce((sum, p) => sum + p.reading_count, 0)
        };
      }

      const stddev = matchingPattern.stddev_power || 15;
      return {
        expectedAvg: matchingPattern.avg_power,
        expectedStddev: stddev,
        expectedRange: [
          matchingPattern.avg_power - 2 * stddev,
          matchingPattern.avg_power + 2 * stddev
        ],
        maxPower: matchingPattern.max_power,
        confidence: matchingPattern.reading_count >= 20 ? 'high' : 'medium',
        readingCount: matchingPattern.reading_count,
        hour: currentHour,
        dow: currentDOW
      };
    } catch (error) {
      console.error('❌ Expected range calculation failed:', error);
      return null;
    }
  }

  static async detectPatternDeviation(userId, currentPower, patterns) {
    try {
      const expectedRange = await this.getExpectedPowerRange(userId, patterns);

      if (!expectedRange) {
        return null; // Insufficient pattern data
      }

      const [minExpected, maxExpected] = expectedRange.expectedRange;

      // Check if current power deviates significantly
      const deviation = currentPower - expectedRange.expectedAvg;
      const zScore = Math.abs(deviation) / (expectedRange.expectedStddev || 1);

      const isDeviation = currentPower > maxExpected || currentPower < minExpected;

      return {
        isDeviation,
        currentPower,
        expectedAvg: expectedRange.expectedAvg,
        expectedRange: expectedRange.expectedRange,
        deviation,
        zScore,
        severity: zScore > 3 ? 'high' : zScore > 2 ? 'moderate' : 'normal',
        confidence: expectedRange.confidence
      };
    } catch (error) {
      console.error('❌ Deviation detection failed:', error);
      return null;
    }
  }

  static async recordToggleEvent(userId, relay1Before, relay1After, relay2Before, relay2After, powerBefore, powerAfter) {
    try {
      let toggled = false;
      let socket1Delta = 0;
      let socket2Delta = 0;
      const minMeaningfulDelta = 5;

      if (relay1Before !== relay1After || relay2Before !== relay2After) {
        toggled = true;
        // If exactly one relay toggled, use absolute delta as that socket estimate.
        if (relay1Before !== relay1After && relay2Before === relay2After) {
          socket1Delta = Math.abs((powerAfter || 0) - (powerBefore || 0));
        } else if (relay2Before !== relay2After && relay1Before === relay1After) {
          socket2Delta = Math.abs((powerAfter || 0) - (powerBefore || 0));
        }

        if (socket1Delta < minMeaningfulDelta) socket1Delta = 0;
        if (socket2Delta < minMeaningfulDelta) socket2Delta = 0;

        // Store toggle event
        const query = `
          INSERT INTO relay_toggle_events (user_id, relay1_before, relay1_after, relay2_before, relay2_after, 
                                            power_before, power_after, power_delta, estimated_socket1_power, estimated_socket2_power)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        `;

        await pool.query(query, [
          userId,
          relay1Before,
          relay1After,
          relay2Before,
          relay2After,
          powerBefore,
          powerAfter,
          powerAfter - powerBefore,
          socket1Delta,
          socket2Delta
        ]);
      }

      return toggled;
    } catch (error) {
      console.error('❌ Toggle event recording failed:', error);
      return false;
    }
  }

  static async getSocketSignatures(userId) {
    try {
      // Get recent toggle events (last 30 days)
      const thirtyDaysAgo = moment().subtract(30, 'days').toISOString();

      const query = `
        SELECT
          estimated_socket1_power,
          estimated_socket2_power,
          EXTRACT(EPOCH FROM (NOW() - timestamp)) / 3600.0 AS hours_ago
        FROM relay_toggle_events
        WHERE user_id = $1 AND timestamp > $2
        ORDER BY timestamp DESC
        LIMIT 200
      `;

      const result = await pool.query(query, [userId, thirtyDaysAgo]);

      if (!result.rows.length) {
        return null;
      }

      const socket1Samples = [];
      const socket2Samples = [];

      result.rows.forEach((row) => {
        const s1 = parseFloat(row.estimated_socket1_power || 0);
        const s2 = parseFloat(row.estimated_socket2_power || 0);
        const hoursAgo = Math.max(0, parseFloat(row.hours_ago || 0));
        const recencyWeight = 1 / (1 + (hoursAgo / 24));

        if (s1 > 0) socket1Samples.push({ value: s1, weight: recencyWeight });
        if (s2 > 0) socket2Samples.push({ value: s2, weight: recencyWeight });
      });

      if (socket1Samples.length === 0 && socket2Samples.length === 0) {
        return null;
      }

      const weightedAvg = (samples) => {
        if (!samples.length) return 0;
        const weightedSum = samples.reduce((sum, s) => sum + (s.value * s.weight), 0);
        const weightSum = samples.reduce((sum, s) => sum + s.weight, 0);
        return weightSum > 0 ? (weightedSum / weightSum) : 0;
      };

      const median = (samples) => {
        if (!samples.length) return 0;
        const sorted = [...samples].map(s => s.value).sort((a, b) => a - b);
        const mid = Math.floor(sorted.length / 2);
        return sorted.length % 2 === 0
          ? (sorted[mid - 1] + sorted[mid]) / 2
          : sorted[mid];
      };

      const socket1Avg = weightedAvg(socket1Samples);
      const socket2Avg = weightedAvg(socket2Samples);
      const socket1Median = median(socket1Samples);
      const socket2Median = median(socket2Samples);

      return {
        socket1: {
          avgPower: socket1Avg,
          medianPower: socket1Median,
          totalReadings: socket1Samples.length,
          confidence: socket1Samples.length >= 8 ? 'high' : socket1Samples.length >= 3 ? 'medium' : 'low'
        },
        socket2: {
          avgPower: socket2Avg,
          medianPower: socket2Median,
          totalReadings: socket2Samples.length,
          confidence: socket2Samples.length >= 8 ? 'high' : socket2Samples.length >= 3 ? 'medium' : 'low'
        }
      };
    } catch (error) {
      console.error('❌ Socket signature retrieval failed:', error);
      return null;
    }
  }

  static async attributePowerToSocket(userId, currentPower, relay1, relay2, socketSignatures) {
    try {
      const r1 = parseInt(relay1) === 1 ? 1 : 0;
      const r2 = parseInt(relay2) === 1 ? 1 : 0;

      if (r1 === 0 && r2 === 0) {
        return { socket: 0, power: 0, confidence: 'LOW' };
      }

      // If only one relay on, it's simple
      if (r1 === 1 && r2 === 0) {
        return { socket: 1, power: currentPower, confidence: 'HIGH' };
      }
      if (r2 === 1 && r1 === 0) {
        return { socket: 2, power: currentPower, confidence: 'HIGH' };
      }

      // Both relays on, use learned signatures
      if (r1 === 1 && r2 === 1 && socketSignatures) {
        const s1 = socketSignatures.socket1 || {};
        const s2 = socketSignatures.socket2 || {};

        const s1Count = parseInt(s1.totalReadings || 0);
        const s2Count = parseInt(s2.totalReadings || 0);
        const s1Base = parseFloat(s1.medianPower || s1.avgPower || 0);
        const s2Base = parseFloat(s2.medianPower || s2.avgPower || 0);

        if (s1Base > 0 && s2Base > 0 && s1Count >= 2 && s2Count >= 2) {
          const total = s1Base + s2Base;
          const socket1Power = (s1Base / total) * currentPower;
          const socket2Power = (s2Base / total) * currentPower;
          const diff = Math.abs(socket1Power - socket2Power);
          const minDominance = Math.max(currentPower * 0.12, 20);

          if (diff < minDominance) {
            return {
              socket: 0,
              power: currentPower,
              confidence: 'LOW',
              socket1Estimated: socket1Power,
              socket2Estimated: socket2Power,
            };
          }

          const dominantSocket = socket1Power > socket2Power ? 1 : 2;
          const dominantPower = socket1Power > socket2Power ? socket1Power : socket2Power;
          const confidence = (s1Count >= 8 && s2Count >= 8 && diff > currentPower * 0.25)
            ? 'HIGH'
            : 'MEDIUM';

          return {
            socket: dominantSocket,
            power: dominantPower,
            confidence,
            socket1Estimated: socket1Power,
            socket2Estimated: socket2Power,
          };
        } else if (s1Base > 0 && s1Count >= 2) {
          return { socket: 1, power: currentPower, confidence: 'LOW' };
        } else if (s2Base > 0 && s2Count >= 2) {
          return { socket: 2, power: currentPower, confidence: 'LOW' };
        }
      }

      return { socket: 0, power: currentPower, confidence: 'LOW' };
    } catch (error) {
      console.error('❌ Power attribution failed:', error);
      return { socket: 0, power: currentPower, confidence: 'LOW' };
    }
  }

  static async ensureSchema() {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS user_power_patterns (
          id SERIAL PRIMARY KEY,
          user_id TEXT NOT NULL UNIQUE,
          pattern_data JSONB NOT NULL,
          analyzed_at TIMESTAMP DEFAULT NOW()
        )
      `);

      await pool.query(`
        CREATE TABLE IF NOT EXISTS relay_toggle_events (
          id SERIAL PRIMARY KEY,
          user_id TEXT NOT NULL,
          timestamp TIMESTAMP DEFAULT NOW(),
          relay1_before INT,
          relay1_after INT,
          relay2_before INT,
          relay2_after INT,
          power_before NUMERIC,
          power_after NUMERIC,
          power_delta NUMERIC,
          estimated_socket1_power NUMERIC,
          estimated_socket2_power NUMERIC
        )
      `);

      await pool.query(`
        CREATE INDEX IF NOT EXISTS idx_relay_toggle_user_time 
        ON relay_toggle_events(user_id, timestamp DESC)
      `);

      await pool.query(`
        CREATE TABLE IF NOT EXISTS alert_dismissals (
          id SERIAL PRIMARY KEY,
          user_id TEXT NOT NULL,
          alert_id TEXT NOT NULL UNIQUE,
          alert_data JSONB NOT NULL,
          dismissed_at TIMESTAMP DEFAULT NOW(),
          re_alert_scheduled_for TIMESTAMP,
          re_alerted BOOLEAN DEFAULT FALSE,
          re_alert_sent_at TIMESTAMP
        )
      `);

      await pool.query(`
        CREATE INDEX IF NOT EXISTS idx_alert_dismissals_realert 
        ON alert_dismissals(user_id, re_alert_scheduled_for)
        WHERE re_alerted = FALSE
      `);

      console.log('✅ Pattern analysis schema initialized');
    } catch (error) {
      console.error('❌ Schema initialization failed:', error);
      throw error;
    }
  }
}

module.exports = PatternAnalysisService;
