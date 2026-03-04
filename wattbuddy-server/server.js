const express = require('express');
const cors = require('cors');
const http = require('http');
const socketIO = require('socket.io');
const moment = require('moment');
const cron = require('node-cron');
const axios = require('axios');

const app = express();
const server = http.createServer(app);

// ESP32 IP Address - Update this to match your ESP32's IP
const ESP32_IP = '10.185.178.50';
const ESP32_PORT = 80;

// Use Socket.io to broadcast data to your Flutter App/Dashboard
const io = socketIO(server, { 
    cors: { origin: "*" },
    transports: ['websocket', 'polling'] 
});

// ============ IN-MEMORY CACHE ============
let esp32LatestData = {
  voltage: 0, 
  current: 0, 
  power: 0, 
  energy: 0,
  relay1: 0, 
  relay2: 0, 
  userId: null,
  timestamp: new Date().toISOString()
};

// Track last database write to optimize database growth
let lastDbWrite = {
  timestamp: 0,
  energy_consumed: 0
};

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ============ SERVICES & ROUTES ============
const ESP32StorageService = require('./services/esp32StorageService');
const RealtimeGraphService = require('./services/realtimeGraphService');
const MLPredictionService = require('./services/mlPredictionService');
const PowerLimitService = require('./services/powerLimitService');
const MonthlyUsageService = require('./services/monthlyUsageService');

const authRoutes = require('./routes/authRoutes');
const mlRoutes = require('./routes/mlRoutes');
const usageRoutes = require('./routes/usageRoutes');
const predictionRoutes = require('./routes/predictionRoutes');
const notificationRoutes = require('./routes/notificationRoutes');

app.use('/api/auth', authRoutes);
app.use('/api/ml', mlRoutes);
app.use('/api/usage', usageRoutes);
app.use('/api/predictions', predictionRoutes);
app.use('/api/notifications', notificationRoutes);

// ============ TEST ROUTE ============
app.get('/', (req, res) => {
  res.send('🚀 WattBuddy Server Running');
});

// ============ 2️⃣ ESP32 DATA RECEIVER (MODIFIED TO SAVE TO DB) ============
app.post('/api/esp32/data', async (req, res) => {
  try {
    // Accept either `energy` or `energy_consumed` from different firmware versions
    const { voltage, current, power, energy, energy_consumed, relay1, relay2, userId, dominantRelay, dominantPower } = req.body;
    const pool = require('./db'); // Ensure your DB connection is imported
    const now = Date.now();

    // DEBUG: Log raw incoming data
    console.log(`📥 [ESP32 POST RECEIVED] Raw body:`, JSON.stringify(req.body));

    // Normalize and parse incoming values (use whichever energy key is present)
    const parsedVoltage = parseFloat(voltage) || 0;
    const parsedCurrent = parseFloat(current) || 0;
    const parsedPower = parseFloat(power) || 0;
    const parsedEnergy = parseFloat(energy !== undefined ? energy : energy_consumed) || 0;
    const parsedRelay1 = parseInt(relay1) || 0;
    const parsedRelay2 = parseInt(relay2) || 0;
    const parsedDominantRelay = parseInt(dominantRelay) || 0;
    const parsedDominantPower = parseFloat(dominantPower) || 0;

    // DEBUG: Log parsed values
    console.log(`✅ [PARSED VALUES] V=${parsedVoltage}, I=${parsedCurrent}, P=${parsedPower}, E=${parsedEnergy}, R1=${parsedRelay1}, R2=${parsedRelay2}`);

    // 1. Update Cache (Always for real-time Socket.io) with parsed numeric values
    // Use in-place update so other modules holding a reference see changes
    Object.assign(esp32LatestData, {
      voltage: parsedVoltage,
      current: parsedCurrent,
      power: parsedPower,
      energy: parsedEnergy,
      relay1: parsedRelay1,
      relay2: parsedRelay2,
      userId: (userId !== undefined && userId !== null) ? String(userId) : null,
      dominantRelay: parsedDominantRelay,
      dominantPower: parsedDominantPower,
      timestamp: new Date().toISOString()
    });

    // DEBUG: Log what was stored in cache
    console.log(`💾 [CACHE UPDATED]`, JSON.stringify(esp32LatestData));
    
    // 3. Broadcast to Flutter (Every 5 seconds for live dashboard)
    io.emit('live_data_update', esp32LatestData);
    
    // ============ ML-BASED ANOMALY DETECTION & REAL-TIME ALERT ============
    // Use statistical ML (Z-score) on recent history instead of a fixed threshold.
    try {
      const mlResult = await MLPredictionService.detectLatestAnomaly(userId || '8');

      if (mlResult && mlResult.isAnomaly) {
        const currentPower = mlResult.latestPower ?? parsedPower;

        // Identify which socket is causing the spike
        let problematicSocket = "Both Sockets";
        let dominantInfo = '';

        if (parsedDominantRelay === 1 || parsedDominantRelay === 2) {
          problematicSocket = parsedDominantRelay === 1 ? "Socket 1" : "Socket 2";
          if (parsedDominantPower > 0) {
            dominantInfo = ` (~${parsedDominantPower.toFixed(0)}W from this device)`;
          }
        } else {
          // Fallback: infer from relay states if diagnosis not available
          if (relay1 === 1 && relay2 === 0) {
            problematicSocket = "Socket 1";
          } else if (relay2 === 1 && relay1 === 0) {
            problematicSocket = "Socket 2";
          }
        }

        const baselineInfo = mlResult.mean != null && mlResult.stdDev != null
          ? ` (baseline ≈ ${mlResult.mean.toFixed(0)}W, z≈${mlResult.zScore?.toFixed(2) ?? '?.??'})`
          : '';

        // Emit real-time alert to Flutter app via WebSocket
        io.emit('anomaly_alert', {
          isAbnormal: true,
          anomalySocket: problematicSocket,
          currentPower: currentPower,
          threshold: mlResult.mean ?? 0,
          dominantRelay: parsedDominantRelay,
          dominantPower: parsedDominantPower,
          message: `⚠️ ML anomaly detected on ${problematicSocket}! Power: ${currentPower.toFixed(0)}W${dominantInfo}${baselineInfo}`,
          timestamp: new Date().toISOString(),
          userId: userId || '8'
        });

        console.log(`🚨 [ML ANOMALY ALERT] ${problematicSocket} - Power: ${currentPower}W, z≈${mlResult.zScore?.toFixed(2) ?? 'N/A'}`);
      }
    } catch (mlErr) {
      console.error('❌ ML anomaly detection failed:', mlErr);
    }
    
    // 2. SAVE TO DATABASE (Optimized: Only write if conditions met)
    // Condition 1: 1 minute (60000ms) has passed since last write
    // Condition 2: Energy changed by at least 0.001 kWh
    const timeSinceLastWrite = now - lastDbWrite.timestamp;
    const energyDifference = Math.abs(parsedEnergy - (parseFloat(lastDbWrite.energy_consumed) || 0));
    const shouldWrite = timeSinceLastWrite >= 60000 || energyDifference >= 0.001;
    
    if (shouldWrite) {
      // Compute increment since last saved energy (only positive deltas)
      const incomingEnergy = parsedEnergy;
      const lastEnergy = parseFloat(lastDbWrite.energy_consumed) || incomingEnergy;
      const increment = incomingEnergy > lastEnergy ? (incomingEnergy - lastEnergy) : 0;

      const insertQuery = `
        INSERT INTO "EnergyReadings" (user_id, voltage, current, power, energy_consumed, relay1, relay2, timestamp)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
      `;
      await pool.query(insertQuery, [userId || '8', parsedVoltage, parsedCurrent, parsedPower, incomingEnergy, parsedRelay1, parsedRelay2]);

      // Update aggregate total in UserStats to protect against energy resets
      try {
        const updateQuery = `
          UPDATE "UserStats"
          SET total_energy = total_energy + $1
          WHERE user_id = $2
        `;
        const updateRes = await pool.query(updateQuery, [increment, userId || '8']);

        // If no row was updated, insert a new stats row
        if (updateRes.rowCount === 0 && increment > 0) {
          const insertStats = `
            INSERT INTO "UserStats" (user_id, total_energy, created_at)
            VALUES ($1, $2, NOW())
          `;
          await pool.query(insertStats, [userId || '8', increment]);
        }
      } catch (errStats) {
        console.error('❌ Failed to update UserStats:', errStats);
      }

      // Update tracking variables
      lastDbWrite.timestamp = now;
      lastDbWrite.energy_consumed = incomingEnergy;

      // ALSO: write a normalized row into the legacy `energy_readings` table
      // so services expecting `energy_readings` (power_consumption, recorded_at) work.
      try {
        const uid = parseInt(userId) || 8;
        await pool.query(
          `INSERT INTO energy_readings (user_id, power_consumption, voltage, current, recorded_at)
           VALUES ($1, $2, $3, $4, NOW())`,
          [uid, parsedPower, parsedVoltage, parsedCurrent]
        );
        console.log('💾 [ALT DB SAVE] energy_readings row inserted');
      } catch (errAlt) {
        console.error('❌ Failed to insert into energy_readings fallback:', errAlt.message || errAlt);
      }
      console.log(`📊 [ESP32 DB Save] V: ${parsedVoltage}V | I: ${parsedCurrent}A | P: ${parsedPower}W | E: ${incomingEnergy}kWh | inc: ${increment.toFixed(6)} | User: ${userId || '8'}`);
    } else {
      // Log cache-only updates
      console.log(`📡 [ESP32 Live] V: ${parsedVoltage}V | I: ${parsedCurrent}A | P: ${parsedPower}W | E: ${parsedEnergy}kWh (Cache only)`);
    }
    
    res.json({ success: true, data: esp32LatestData, dbWrite: shouldWrite });
  } catch (error) {
    console.error('❌ Error processing ESP32 data:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============ GET LATEST DATA ============
app.get('/esp32/latest', (req, res) => {
  try {
    res.json({ success: true, data: esp32LatestData });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ USAGE SUMMARY (Fixes Last Month & Current Month) ============
app.get('/api/usage/summary/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const pool = require('./db');

        const summaryQuery = `
            SELECT 
                (SELECT COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0)
                 FROM "EnergyReadings"
                 WHERE user_id = $1::text 
                   AND timestamp >= DATE_TRUNC('month', CURRENT_DATE)
                ) as current_month,

                (SELECT COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0)
                 FROM "EnergyReadings"
                 WHERE user_id = $1::text 
                   AND timestamp >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
                   AND timestamp < DATE_TRUNC('month', CURRENT_DATE)
                ) as last_month,

                COALESCE(AVG(power), 0) as historical_avg_power
            FROM "EnergyReadings"
            WHERE user_id = $1::text
            LIMIT 1
        `;
        
        const result = await pool.query(summaryQuery, [userId]);
        const data = result.rows[0] || {};

        const currentMonthKwh = parseFloat(data.current_month || 0);
        const lastMonthKwh = parseFloat(data.last_month || 0);
        const historicalAvgPower = parseFloat(data.historical_avg_power || 0);

        // Simple anomaly detection based on latest power reading vs historical average
        let isAbnormal = false;
        let anomalySocket = null;
        let currentPower = 0;

        try {
          const latestRes = await pool.query(
            `SELECT power, relay1, relay2, timestamp
             FROM "EnergyReadings"
             WHERE user_id = $1::text
             ORDER BY timestamp DESC
             LIMIT 1`,
            [userId]
          );

          if (latestRes.rows.length > 0) {
            const latest = latestRes.rows[0];
            currentPower = parseFloat(latest.power || 0);

            const relay1 = parseInt(latest.relay1 ?? 0);
            const relay2 = parseInt(latest.relay2 ?? 0);

            // Use historical average when available, otherwise fall back to 150W
            const baseline = Number.isFinite(historicalAvgPower) && historicalAvgPower > 0
              ? historicalAvgPower
              : 75;
            const threshold = baseline * 2.0; // match ESP32/real-time anomaly threshold

            if (currentPower > threshold) {
              isAbnormal = true;

              if (relay1 === 1 && relay2 !== 1) {
                anomalySocket = 'Socket 1';
              } else if (relay2 === 1 && relay1 !== 1) {
                anomalySocket = 'Socket 2';
              } else {
                anomalySocket = 'Both Sockets';
              }
            }
          }
        } catch (anomalyErr) {
          console.warn('⚠️ Failed to compute anomaly summary:', anomalyErr.message || anomalyErr);
        }

        res.json({
            success: true,
            currentMonthKwh,
            lastMonthKwh,
            historicalAvg: historicalAvgPower,
            historicalAvgPower,
            daysElapsed: new Date().getDate(),
            // Anomaly fields expected by Flutter `BillPredictionScreen`
            isAbnormal,
            anomalySocket,
            currentPower,
        });
    } catch (err) {
        console.error('❌ Usage Summary Error:', err);
        res.status(500).json({ success: false, error: err.message });
    }
});

// ============ DAILY HISTORY (For Bar Chart) ============
app.get('/api/usage/daily-history/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const pool = require('./db');
        const query = `
            WITH daily_data AS (
                SELECT 
                    EXTRACT(DAY FROM timestamp)::int as day,
                    MAX(energy_consumed) as max_e,
                    MIN(energy_consumed) as min_e
                FROM "EnergyReadings"
                WHERE user_id = $1::text 
                  AND timestamp >= DATE_TRUNC('month', CURRENT_DATE)
                GROUP BY day
            )
            SELECT 
                d.day,
                COALESCE(
                    CASE 
                        WHEN max_e = min_e THEN 0.15 -- Mock value if only 1 reading exists for demo
                        ELSE max_e - min_e 
                    END, 0
                ) as kwh
            FROM (SELECT generate_series(1, EXTRACT(DAY FROM CURRENT_DATE)::int) as day) d
            LEFT JOIN daily_data ON d.day = daily_data.day
            ORDER BY d.day ASC
        `;
        const result = await pool.query(query, [userId]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ============ FETCH CALCULATED BILL FROM SQL VIEW ============
app.get('/api/billing/current/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const pool = require('./db');
        
        // Prefer SQL View (if present), but gracefully fallback if it doesn't exist.
        try {
            const result = await pool.query(
                'SELECT * FROM view_user_bills WHERE user_id = $1',
                [userId]
            );

            if (result.rows.length > 0) {
                return res.json({ success: true, billing: result.rows[0], source: 'view_user_bills' });
            }
        } catch (viewErr) {
            console.warn('⚠️ view_user_bills unavailable, falling back:', viewErr.message || viewErr);
        }

        // Fallback: compute current-month usage from EnergyReadings
        // Usage = MAX(energy_consumed) - MIN(energy_consumed) this month
        const usageQuery = `
            SELECT
                COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) AS total_units_kwh
            FROM "EnergyReadings"
            WHERE user_id = $1::text
              AND timestamp >= DATE_TRUNC('month', CURRENT_DATE)
        `;

        const usageRes = await pool.query(usageQuery, [userId]);
        const kwh = parseFloat(usageRes.rows?.[0]?.total_units_kwh) || 0;

        // Simple tariff fallback (aligns with Flutter defaults)
        const baseCharge = 50;
        const ratePerKwh = 10;
        const billRs = baseCharge + (kwh * ratePerKwh);

        return res.json({
            success: true,
            source: 'EnergyReadings_fallback',
            billing: {
                user_id: userId,
                total_units_kwh: kwh,
                slab_bill_rs: billRs,
                base_charge_rs: baseCharge,
                rate_per_kwh: ratePerKwh,
            }
        });
    } catch (err) {
        console.error('❌ Error fetching current bill:', err);
        res.status(500).json({ success: false, error: err.message });
    }
});

// ============ FETCH HISTORICAL BILLS ============
// Used by the Flutter `BillHistoryScreen` and `BillHistoryService`
app.get('/api/billing/history/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const pool = require('./db');

        // Compute monthly usage and bill for past months using energy readings.
        // Amount calculation mirrors the same fallback logic used above.
        const historyQuery = `
            SELECT
                to_char(month, 'Mon YYYY') AS period,
                to_char(month + interval '1 month' - interval '1 day', 'Mon DD, YYYY') AS "dueDate",
                (kwh * 10 + 50)::numeric AS amount,
                kwh AS units,
                CASE WHEN kwh > 0 THEN 'paid' ELSE 'due' END AS status
            FROM (
                SELECT
                    date_trunc('month', timestamp) AS month,
                    COALESCE(MAX(energy_consumed) - MIN(energy_consumed), 0) AS kwh
                FROM "EnergyReadings"
                WHERE user_id = $1::text
                GROUP BY 1
                ORDER BY 1 DESC
                LIMIT 12
            ) sub;
        `;

        const result = await pool.query(historyQuery, [userId]);
        return res.json({ success: true, bills: result.rows });
    } catch (err) {
        console.error('❌ Error fetching billing history:', err);
        res.status(500).json({ success: false, error: err.message });
    }
});

// ============ POWER-LIMIT ENDPOINTS ============
app.post('/api/power-limit/check', async (req, res) => {
  try {
    const { userId, currentUsage, dailyLimit } = req.body;
    const notification = await PowerLimitService.checkPowerLimit(userId, currentUsage, dailyLimit);
    res.json({ success: true, ...notification });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/power-limit/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const settings = await PowerLimitService.getPowerLimitSettings(userId);
    res.json({ success: true, ...settings });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ GRAPH ENDPOINTS ============
app.get('/api/graph/live/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { minutes = 60 } = req.query;
    const data = await RealtimeGraphService.getLiveGraphData(userId, minutes);
    res.json({ success: true, graphData: data });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ DEBUG: recent energy rows (no psql needed) ============
app.get('/api/debug/recent-energy', async (req, res) => {
  try {
    const pool = require('./db');
    const limit = parseInt(req.query.limit) || 20;

    // Prefer canonical snake_case table used by graph service
    try {
      const result = await pool.query(
        `SELECT recorded_at as timestamp, power_consumption as power, voltage, current
         FROM energy_readings
         ORDER BY recorded_at DESC
         LIMIT $1`,
        [limit]
      );

      return res.json({ success: true, source: 'energy_readings', rows: result.rows });
    } catch (e) {
      // Fallback to older "EnergyReadings" table
      const fallback = await pool.query(
        `SELECT timestamp as timestamp, power as power, voltage, current
         FROM "EnergyReadings"
         ORDER BY timestamp DESC
         LIMIT $1`,
        [limit]
      );
      return res.json({ success: true, source: 'EnergyReadings', rows: fallback.rows });
    }
  } catch (err) {
    console.error('❌ Debug recent-energy failed:', err);
    res.status(500).json({ success: false, error: err.message || err });
  }
});

// ============ ML PREDICTION ENDPOINTS ============
app.get('/api/ml-predict/next-hour/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const prediction = await MLPredictionService.predictNextHour(userId);
    res.json({ success: true, prediction });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ RELAY CONTROL ENDPOINTS ============
// Helper function to send command to ESP32
async function sendRelayCommandToESP32(relayNumber, command) {
  const url = `http://${ESP32_IP}:${ESP32_PORT}/relay${relayNumber}/${command}`;
  console.log(`📡 Sending relay command to ESP32: ${url}`);
  
  try {
    const response = await axios.get(url, { timeout: 5000 });
    console.log(`✅ ESP32 responded: ${response.status} - ${response.data}`);
    return { success: true, esp32Response: response.data };
  } catch (error) {
    console.error(`❌ Failed to communicate with ESP32: ${error.message}`);
    return { success: false, error: error.message };
  }
}

// Turn off Socket 1 relay
app.get('/api/relay/relay1/off', async (req, res) => {
  try {
    console.log('🔴 [RELAY 1 OFF] User triggered shutdown');
    
    // Send actual command to ESP32
    const esp32Result = await sendRelayCommandToESP32(1, 'off');
    
    // Emit relay status update to all connected clients
    io.emit('relay_status', {
      relay: 1,
      status: 'off',
      message: esp32Result.success ? 'Socket 1 has been safely disconnected' : 'Failed to disconnect Socket 1',
      esp32Connected: esp32Result.success,
      timestamp: new Date().toISOString()
    });
    
    // Update cache
    esp32LatestData.relay1 = 0;
    
    if (esp32Result.success) {
      res.json({ 
        success: true, 
        message: 'Socket 1 relay turned OFF',
        relay: 1,
        status: 'off'
      });
    } else {
      res.status(500).json({ 
        success: false, 
        error: 'Failed to connect to ESP32: ' + esp32Result.error,
        message: 'Could not reach ESP32 device. Is it connected to the network?'
      });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Turn off Socket 2 relay
app.get('/api/relay/relay2/off', async (req, res) => {
  try {
    console.log('🔴 [RELAY 2 OFF] User triggered shutdown');
    
    // Send actual command to ESP32
    const esp32Result = await sendRelayCommandToESP32(2, 'off');
    
    // Emit relay status update to all connected clients
    io.emit('relay_status', {
      relay: 2,
      status: 'off',
      message: esp32Result.success ? 'Socket 2 has been safely disconnected' : 'Failed to disconnect Socket 2',
      esp32Connected: esp32Result.success,
      timestamp: new Date().toISOString()
    });
    
    // Update cache
    esp32LatestData.relay2 = 0;
    
    if (esp32Result.success) {
      res.json({ 
        success: true, 
        message: 'Socket 2 relay turned OFF',
        relay: 2,
        status: 'off'
      });
    } else {
      res.status(500).json({ 
        success: false, 
        error: 'Failed to connect to ESP32: ' + esp32Result.error,
        message: 'Could not reach ESP32 device. Is it connected to the network?'
      });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Turn on Socket 1 relay
app.get('/api/relay/relay1/on', async (req, res) => {
  try {
    console.log('🟢 [RELAY 1 ON] User enabled socket');
    
    // Send actual command to ESP32
    const esp32Result = await sendRelayCommandToESP32(1, 'on');
    
    io.emit('relay_status', {
      relay: 1,
      status: 'on',
      message: esp32Result.success ? 'Socket 1 has been re-enabled' : 'Failed to enable Socket 1',
      esp32Connected: esp32Result.success,
      timestamp: new Date().toISOString()
    });
    
    // Update cache
    esp32LatestData.relay1 = 1;
    
    if (esp32Result.success) {
      res.json({ 
        success: true, 
        message: 'Socket 1 relay turned ON',
        relay: 1,
        status: 'on'
      });
    } else {
      res.status(500).json({ 
        success: false, 
        error: 'Failed to connect to ESP32: ' + esp32Result.error,
        message: 'Could not reach ESP32 device. Is it connected to the network?'
      });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Turn on Socket 2 relay
app.get('/api/relay/relay2/on', async (req, res) => {
  try {
    console.log('🟢 [RELAY 2 ON] User enabled socket');
    
    // Send actual command to ESP32
    const esp32Result = await sendRelayCommandToESP32(2, 'on');
    
    io.emit('relay_status', {
      relay: 2,
      status: 'on',
      message: esp32Result.success ? 'Socket 2 has been re-enabled' : 'Failed to enable Socket 2',
      esp32Connected: esp32Result.success,
      timestamp: new Date().toISOString()
    });
    
    // Update cache
    esp32LatestData.relay2 = 1;
    
    if (esp32Result.success) {
      res.json({ 
        success: true, 
        message: 'Socket 2 relay turned ON',
        relay: 2,
        status: 'on'
      });
    } else {
      res.status(500).json({ 
        success: false, 
        error: 'Failed to connect to ESP32: ' + esp32Result.error,
        message: 'Could not reach ESP32 device. Is it connected to the network?'
      });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get current relay status
app.get('/api/relay/status', (req, res) => {
  try {
    res.json({
      success: true,
      relay1: esp32LatestData.relay1,
      relay2: esp32LatestData.relay2,
      timestamp: esp32LatestData.timestamp
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ SOCKET.IO LOGIC ============
io.on('connection', (socket) => {
  console.log(`✅ Dashboard Connected: ${socket.id}`);

  // Send the most recent data immediately upon connection
  socket.emit('live_data_update', esp32LatestData);

  socket.on('disconnect', () => {
    console.log('🔌 Dashboard Disconnected');
  });
});

// ============ DEBUG: FORCE ANOMALY ALERT (for Flutter testing) ============
// Hit this in a browser: http://localhost:4000/api/debug/trigger-anomaly
// You should see an alert in the app if Socket.io + handlers are wired.
app.get('/api/debug/trigger-anomaly', (req, res) => {
  try {
    const payload = {
      isAbnormal: true,
      anomalySocket: 'Socket 1',
      currentPower: 250,
      threshold: 150,
      dominantRelay: 1,
      dominantPower: 250,
      message: '⚠️ Test high usage on Socket 1 (debug endpoint)',
      timestamp: new Date().toISOString(),
      userId: 'debug',
    };
    io.emit('anomaly_alert', payload);
    console.log('🧪 [DEBUG] Emitted test anomaly_alert:', payload);
    res.json({ success: true, emitted: payload });
  } catch (e) {
    console.error('❌ Failed to emit debug anomaly:', e);
    res.status(500).json({ success: false, error: e.message || String(e) });
  }
});

// ============ MONTHLY BILLING RESET (CRON JOB) ============
cron.schedule('0 0 1 * *', async () => {
    try {
        const pool = require('./db');
        console.log('📅 Running Monthly Billing Reset...');
        await pool.query('SELECT reset_monthly_bill();');
        console.log('✅ Monthly billing snapshots saved and reset.');
    } catch (err) {
        console.error('❌ Monthly reset failed:', err);
    }
});

// Ensure supporting tables exist (safe to run every start)
try {
  const pool = require('./db');
  (async () => {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS "UserStats" (
          user_id TEXT PRIMARY KEY,
          total_energy NUMERIC DEFAULT 0,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      `);
      console.log('✅ Ensured table "UserStats" exists');
    } catch (e) {
      console.error('❌ Error ensuring UserStats table exists:', e);
    }
  })();
} catch (e) {
  console.error('❌ Could not initialize DB helper for migrations:', e);
}

// ============ START SERVER ============
const PORT = process.env.PORT || 4000;
server.listen(PORT, '0.0.0.0', () => {
  console.log('\n🚀 ================================');
  console.log('   WattBuddy Server: ONLINE');
  console.log('================================');
  console.log(`🌐 Listening at: http://0.0.0.0:${PORT}`);
  console.log('📱 Waiting for data from Flutter App...');
  console.log('================================\n');
});

module.exports = { app, server, io, esp32LatestData };

