const express = require('express');
const cors = require('cors');
const http = require('http');
const socketIO = require('socket.io');
const moment = require('moment');

const app = express();
const server = http.createServer(app);
const io = socketIO(server, { cors: { origin: "*" } });

// ============ MIDDLEWARE ============
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ============ SERVICES ============
const ESP32StorageService = require('./services/esp32StorageService');
const RealtimeGraphService = require('./services/realtimeGraphService');
const MLPredictionService = require('./services/mlPredictionService');
const PowerLimitService = require('./services/powerLimitService');
const MonthlyUsageService = require('./services/monthlyUsageService');

// ============ ROUTES ============
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
  res.send('🚀 WattBuddy Server Running with All 4 Features!');
});

// ============ 1️⃣ POWER-LIMIT NOTIFICATION ENDPOINTS ============
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

app.post('/api/power-limit/set', async (req, res) => {
  try {
    const { userId, dailyLimit } = req.body;
    const result = await PowerLimitService.setPowerLimit(userId, dailyLimit);
    res.json({ success: true, limit: result });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ 2️⃣ ESP32 DATA STORAGE ENDPOINTS ============
app.post('/api/esp32/data', async (req, res) => {
  try {
    const { userId, ...reading } = req.body;
    const stored = await ESP32StorageService.storeReading(userId, reading);
    
    // Broadcast to real-time graph clients
    io.to(`user_${userId}`).emit('live_data_update', reading);
    
    res.json({ success: true, data: stored });
  } catch (error) {
    console.error('Error storing ESP32 data:', error);
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/esp32/latest/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 100 } = req.query;
    const readings = await ESP32StorageService.getLatestReadings(userId, limit);
    res.json({ success: true, readings });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/esp32/stats/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { date = moment().format('YYYY-MM-DD') } = req.query;
    const stats = await ESP32StorageService.getDailySummary(userId, date);
    res.json({ success: true, stats });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/esp32/hourly/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { date = moment().format('YYYY-MM-DD') } = req.query;
    const hourly = await ESP32StorageService.getHourlyStats(userId, date);
    res.json({ success: true, hourly });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ 3️⃣ LIVE REAL-TIME GRAPH ENDPOINTS ============
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

app.get('/api/graph/comparison/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const comparison = await RealtimeGraphService.getComparisonData(userId);
    res.json({ success: true, ...comparison });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ 4️⃣ ML PREDICTION ENDPOINTS ============
app.get('/api/ml-predict/next-hour/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const prediction = await MLPredictionService.predictNextHour(userId);
    res.json({ success: true, prediction });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/ml-predict/next-day/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const prediction = await MLPredictionService.predictNextDay(userId);
    res.json({ success: true, prediction });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/ml-predict/anomalies/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const anomalies = await MLPredictionService.detectAnomalies(userId);
    res.json({ success: true, ...anomalies });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/ml-predict/recommendations/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const recommendations = await MLPredictionService.getRecommendations(userId);
    res.json({ success: true, ...recommendations });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ WEBSOCKET (Socket.io) FOR REAL-TIME UPDATES ============
io.on('connection', (socket) => {
  console.log(`✅ New WebSocket connection: ${socket.id}`);

  // Join user to their room for real-time updates
  socket.on('join_user', (userId) => {
    socket.join(`user_${userId}`);
    console.log(`📡 User ${userId} joined real-time channel`);
  });

  // Broadcast live data when ESP32 sends data
  socket.on('esp32_data', async (data) => {
    const { userId, ...reading } = data;
    io.to(`user_${userId}`).emit('live_data_update', {
      timestamp: new Date().toISOString(),
      ...reading
    });
  });

  // Get live graph data on demand
  socket.on('request_graph_data', async (userId) => {
    const data = await RealtimeGraphService.getLiveGraphData(userId);
    io.to(`user_${userId}`).emit('graph_data', data);
  });

  socket.on('disconnect', () => {
    console.log(`🔌 WebSocket disconnected: ${socket.id}`);
  });
});

// ============ START SERVER ============
const PORT = process.env.PORT || 4000;
server.listen(PORT, '0.0.0.0', () => {
  console.log('\n🚀 ================================');
  console.log('   WattBuddy Server Running');
  console.log('================================');
  console.log(`🌐 http://0.0.0.0:${PORT}`);
  console.log('\n✨ Features Enabled:');
  console.log('1️⃣  Power-Limit Notifications');
  console.log('2️⃣  ESP32 Data Storage (PostgreSQL)');
  console.log('3️⃣  Live Real-Time Graph (WebSocket)');
  console.log('4️⃣  ML Predictions & Anomaly Detection');
  console.log('================================\n');
});

module.exports = { app, server, io };

