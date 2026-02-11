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
  timestamp: new Date()
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
    const { voltage, current, power, energy, relay1, relay2, userId } = req.body;
    const pool = require('./db'); // Ensure your DB connection is imported
    const now = Date.now();

    // 1. Update Cache (Always for real-time Socket.io)
    esp32LatestData = {
      voltage: voltage || 0,
      current: current || 0,
      power: power || 0,
      energy_consumed: energy || 0, // Using the name from your DB
      relay1: relay1 || 0,
      relay2: relay2 || 0,
      timestamp: new Date().toISOString()
    };
    
    // 3. Broadcast to Flutter (Every 5 seconds for live dashboard)
    io.emit('live_data_update', esp32LatestData);
    
    // 2. SAVE TO DATABASE (Optimized: Only write if conditions met)
    // Condition 1: 1 minute (60000ms) has passed since last write
    // Condition 2: Energy changed by at least 0.001 kWh
    const timeSinceLastWrite = now - lastDbWrite.timestamp;
    const energyDifference = Math.abs((energy || 0) - lastDbWrite.energy_consumed);
    const shouldWrite = timeSinceLastWrite >= 60000 || energyDifference >= 0.001;
    
    if (shouldWrite) {
      const query = `
        INSERT INTO "EnergyReadings" (user_id, voltage, current, power, energy_consumed, relay1, relay2, timestamp)
        VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
      `;
      await pool.query(query, [userId || '8', voltage, current, power, energy, relay1, relay2]);
      
      // Update tracking variables
      lastDbWrite.timestamp = now;
      lastDbWrite.energy_consumed = energy || 0;
      
      console.log(`📊 [ESP32 DB Save] V: ${voltage}V | I: ${current}A | P: ${power}W | E: ${energy}kWh | User: ${userId || '8'}`);
    } else {
      // Log cache-only updates
      console.log(`📡 [ESP32 Live] V: ${voltage}V | I: ${current}A | P: ${power}W | E: ${energy}kWh (Cache only)`);
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

