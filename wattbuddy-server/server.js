const express = require('express');
const cors = require('cors');
const http = require('http');
const socketIO = require('socket.io');
const moment = require('moment');
const cron = require('node-cron');

const app = express();
const server = http.createServer(app);

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
      dominantRelay: parsedDominantRelay,
      dominantPower: parsedDominantPower,
      timestamp: new Date().toISOString()
    });

    // DEBUG: Log what was stored in cache
    console.log(`💾 [CACHE UPDATED]`, JSON.stringify(esp32LatestData));
    
    // 3. Broadcast to Flutter (Every 5 seconds for live dashboard)
    io.emit('live_data_update', esp32LatestData);
    
    // ============ ANOMALY DETECTION & REAL-TIME ALERT ============
    // Detect power spikes > 2x baseline (baseline = 75W, threshold = 150W)
    const baselineAvgPower = 75; // Conservative baseline
    const anomalyThreshold = baselineAvgPower * 2.0; // 150W
    const currentPower = parsedPower;
    
    if (currentPower > anomalyThreshold) {
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
      
      // Emit real-time alert to Flutter app via WebSocket
      io.emit('anomaly_alert', {
        isAbnormal: true,
        anomalySocket: problematicSocket,
        currentPower: currentPower,
        threshold: anomalyThreshold,
        dominantRelay: parsedDominantRelay,
        dominantPower: parsedDominantPower,
        message: `⚠️ High usage detected on ${problematicSocket}! Power: ${currentPower.toFixed(0)}W${dominantInfo}`,
        timestamp: new Date().toISOString(),
        userId: userId || '8'
      });
      
      console.log(`🚨 [ANOMALY ALERT] ${problematicSocket} - Power: ${currentPower}W (Threshold: ${anomalyThreshold}W, DominantRelay=${parsedDominantRelay}, DominantPower=${parsedDominantPower}W)`);
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

        const query = `
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
        
        const result = await pool.query(query, [userId]);
        const data = result.rows[0];

        res.json({
            success: true,
            currentMonthKwh: parseFloat(data.current_month || 0),
            lastMonthKwh: parseFloat(data.last_month || 0),
            historicalAvg: parseFloat(data.historical_avg_power || 0),
            daysElapsed: new Date().getDate()
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
        
        // This pulls from the SQL View you created in pgAdmin
        const result = await pool.query(
            'SELECT * FROM view_user_bills WHERE user_id = $1', 
            [userId]
        );

        if (result.rows.length > 0) {
            res.json({ success: true, billing: result.rows[0] });
        } else {
            res.json({ success: false, message: "No data found" });
        }
    } catch (err) {
        res.status(500).json({ error: err.message });
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
// Turn off Socket 1 relay
app.get('/api/relay/relay1/off', async (req, res) => {
  try {
    console.log('🔴 [RELAY 1 OFF] User triggered shutdown');
    
    // Emit relay status update to all connected clients
    io.emit('relay_status', {
      relay: 1,
      status: 'off',
      message: 'Socket 1 has been safely disconnected',
      timestamp: new Date().toISOString()
    });
    
    // In production, send HTTP command to ESP32 at http://192.168.6.203/relay1/off
    // For now, we're logging and broadcasting
    
    res.json({ 
      success: true, 
      message: 'Socket 1 relay turned OFF',
      relay: 1,
      status: 'off'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Turn off Socket 2 relay
app.get('/api/relay/relay2/off', async (req, res) => {
  try {
    console.log('🔴 [RELAY 2 OFF] User triggered shutdown');
    
    // Emit relay status update to all connected clients
    io.emit('relay_status', {
      relay: 2,
      status: 'off',
      message: 'Socket 2 has been safely disconnected',
      timestamp: new Date().toISOString()
    });
    
    // In production, send HTTP command to ESP32 at http://192.168.6.203/relay2/off
    
    res.json({ 
      success: true, 
      message: 'Socket 2 relay turned OFF',
      relay: 2,
      status: 'off'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Turn on Socket 1 relay
app.get('/api/relay/relay1/on', async (req, res) => {
  try {
    console.log('🟢 [RELAY 1 ON] User enabled socket');
    
    io.emit('relay_status', {
      relay: 1,
      status: 'on',
      message: 'Socket 1 has been re-enabled',
      timestamp: new Date().toISOString()
    });
    
    res.json({ 
      success: true, 
      message: 'Socket 1 relay turned ON',
      relay: 1,
      status: 'on'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Turn on Socket 2 relay
app.get('/api/relay/relay2/on', async (req, res) => {
  try {
    console.log('🟢 [RELAY 2 ON] User enabled socket');
    
    io.emit('relay_status', {
      relay: 2,
      status: 'on',
      message: 'Socket 2 has been re-enabled',
      timestamp: new Date().toISOString()
    });
    
    res.json({ 
      success: true, 
      message: 'Socket 2 relay turned ON',
      relay: 2,
      status: 'on'
    });
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

