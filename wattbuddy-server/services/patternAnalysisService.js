const pool = require('../db');
const moment = require('moment');

class PatternAnalysisService {
  /**
   * Analyze 30-day hourly + day-of-week consumption patterns for a user
   */
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

      // Store in cache table for quick access
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

  /**
   * Get expected power range for current hour/day based on patterns
   */
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

  /**
   * Detect deviation from learned patterns
   */
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

  /**
   * Track relay toggle events for socket power delta analysis
   */
  static async recordToggleEvent(userId, relay1Before, relay1After, relay2Before, relay2After, powerBefore, powerAfter) {
    try {
      let toggled = false;
      let socket1Delta = 0;
      let socket2Delta = 0;

      if (relay1Before !== relay1After || relay2Before !== relay2After) {
        toggled = true;
        const powerDelta = powerAfter - powerBefore;

        // Simple heuristic: if only relay1 toggled, delta is socket1 power
        if (relay1Before !== relay1After && relay2Before === relay2After) {
          if (relay1After === 0) {
            socket1Delta = powerBefore - powerAfter; // Relay 1 was turned off
          } else {
            socket1Delta = powerAfter - powerBefore; // Relay 1 was turned on
          }
        } else if (relay2Before !== relay2After && relay1Before === relay1After) {
          if (relay2After === 0) {
            socket2Delta = powerBefore - powerAfter;
          } else {
            socket2Delta = powerAfter - powerBefore;
          }
        }

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

  /**
   * Get learned socket power signatures from recent toggle events
   */
  static async getSocketSignatures(userId) {
    try {
      // Get recent toggle events (last 30 days)
      const thirtyDaysAgo = moment().subtract(30, 'days').toISOString();

      const query = `
        SELECT 
          SUM(CASE WHEN estimated_socket1_power > 0 THEN estimated_socket1_power END) as socket1_total,
          COUNT(CASE WHEN estimated_socket1_power > 0 THEN 1 END) as socket1_count,
          AVG(CASE WHEN estimated_socket1_power > 0 THEN estimated_socket1_power END) as socket1_avg,
          SUM(CASE WHEN estimated_socket2_power > 0 THEN estimated_socket2_power END) as socket2_total,
          COUNT(CASE WHEN estimated_socket2_power > 0 THEN 1 END) as socket2_count,
          AVG(CASE WHEN estimated_socket2_power > 0 THEN estimated_socket2_power END) as socket2_avg
        FROM relay_toggle_events
        WHERE user_id = $1 AND timestamp > $2
      `;

      const result = await pool.query(query, [userId, thirtyDaysAgo]);
      const row = result.rows[0];

      if (!row || (row.socket1_count === 0 && row.socket2_count === 0)) {
        return null; // No toggle data yet
      }

      return {
        socket1: {
          avgPower: row.socket1_avg || 0,
          totalReadings: row.socket1_count || 0,
          confidence: (row.socket1_count || 0) >= 10 ? 'high' : 'medium'
        },
        socket2: {
          avgPower: row.socket2_avg || 0,
          totalReadings: row.socket2_count || 0,
          confidence: (row.socket2_count || 0) >= 10 ? 'high' : 'medium'
        }
      };
    } catch (error) {
      console.error('❌ Socket signature retrieval failed:', error);
      return null;
    }
  }

  /**
   * Attribute power to specific socket using signatures + relay state
   */
  static async attributePowerToSocket(userId, currentPower, relay1, relay2, socketSignatures) {
    try {
      // If only one relay on, it's simple
      if (relay1 === 1 && relay2 === 0) {
        return { socket: 1, power: currentPower, confidence: 'HIGH' };
      }
      if (relay2 === 1 && relay1 === 0) {
        return { socket: 2, power: currentPower, confidence: 'HIGH' };
      }

      // Both relays on, use learned signatures
      if (relay1 === 1 && relay2 === 1 && socketSignatures) {
        const s1Avg = socketSignatures.socket1?.avgPower || 0;
        const s2Avg = socketSignatures.socket2?.avgPower || 0;

        if (s1Avg > 0 && s2Avg > 0) {
          // Use ratio to split power
          const total = s1Avg + s2Avg;
          const socket1Power = (s1Avg / total) * currentPower;
          const socket2Power = (s2Avg / total) * currentPower;

          return socket1Power > socket2Power
            ? { socket: 1, power: socket1Power, confidence: 'MEDIUM' }
            : { socket: 2, power: socket2Power, confidence: 'MEDIUM' };
        } else if (s1Avg > 0) {
          return { socket: 1, power: currentPower, confidence: 'LOW' };
        } else if (s2Avg > 0) {
          return { socket: 2, power: currentPower, confidence: 'LOW' };
        }
      }

      return { socket: 0, power: currentPower, confidence: 'LOW' };
    } catch (error) {
      console.error('❌ Power attribution failed:', error);
      return { socket: 0, power: currentPower, confidence: 'LOW' };
    }
  }

  /**
   * Initialize database tables
   */
  static async ensureSchema() {
    try {
      // Pattern analysis cache
      await pool.query(`
        CREATE TABLE IF NOT EXISTS user_power_patterns (
          id SERIAL PRIMARY KEY,
          user_id TEXT NOT NULL UNIQUE,
          pattern_data JSONB NOT NULL,
          analyzed_at TIMESTAMP DEFAULT NOW()
        )
      `);

      // Relay toggle events for socket learning
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

      // Alert dismissals for smart re-alerting
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
