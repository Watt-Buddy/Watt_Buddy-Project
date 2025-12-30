// ESP32 Sensor Data API Endpoints
// Add this to your wattbuddy-server/server.js or create a new route file

const express = require('express');
const router = express.Router();

// ================= SENSOR DATA LOGGING =================
/**
 * POST /api/sensor-data/log
 * Receives sensor readings from ESP32 and stores them in database
 */
router.post('/sensor-data/log', async (req, res) => {
  try {
    const {
      userId,
      deviceId,
      voltage,
      current,
      power,
      relay,
      dailyEnergy,
      monthlyEnergy,
      timestamp
    } = req.body;

    // Validate required fields
    if (!userId || !deviceId) {
      return res.status(400).json({ error: 'userId and deviceId required' });
    }

    // Log the sensor reading
    console.log(`📊 Sensor Data from ${deviceId} [User: ${userId}]`);
    console.log(`   Voltage: ${voltage}V | Current: ${current}A | Power: ${power}W`);
    console.log(`   Daily Energy: ${dailyEnergy} kWh | Monthly: ${monthlyEnergy} kWh`);

    // TODO: Save to MongoDB/PostgreSQL
    // Example MongoDB code:
    /*
    const sensorLog = {
      userId,
      deviceId,
      voltage,
      current,
      power,
      relay,
      dailyEnergy,
      monthlyEnergy,
      timestamp: new Date(timestamp),
      createdAt: new Date()
    };

    // Save to database
    // await db.collection('sensorLogs').insertOne(sensorLog);

    // Update user's current consumption
    // await db.collection('users').updateOne(
    //   { _id: userId },
    //   {
    //     $set: {
    //       currentVoltage: voltage,
    //       currentCurrent: current,
    //       currentPower: power,
    //       dailyEnergy: dailyEnergy,
    //       monthlyEnergy: monthlyEnergy,
    //       lastSensorUpdate: new Date()
    //     }
    //   }
    // );
    */

    // Send success response to ESP32
    res.json({
      success: true,
      message: 'Sensor data logged successfully',
      received: {
        userId,
        deviceId,
        power,
        timestamp
      }
    });

    // TODO: Emit via Socket.IO to connected clients for real-time dashboard update
    // io.to(userId).emit('sensorUpdate', {
    //   voltage,
    //   current,
    //   power,
    //   timestamp: new Date()
    // });

  } catch (error) {
    console.error('❌ Error logging sensor data:', error);
    res.status(500).json({ error: error.message });
  }
});

// ================= ANOMALY LOGGING =================
/**
 * POST /api/anomalies/log
 * Receives anomaly alerts from ESP32
 */
router.post('/anomalies/log', async (req, res) => {
  try {
    const {
      userId,
      deviceId,
      anomalyType,
      voltage,
      current,
      power,
      severity,
      autoShutdown,
      timestamp
    } = req.body;

    if (!userId || !deviceId || !anomalyType) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    console.log(`🚨 ANOMALY ALERT from ${deviceId} [User: ${userId}]`);
    console.log(`   Type: ${anomalyType} | Severity: ${severity}%`);
    console.log(`   V: ${voltage}V | I: ${current}A | P: ${power}W`);
    console.log(`   Auto Shutdown: ${autoShutdown ? 'YES' : 'NO'}`);

    // TODO: Save anomaly to database
    /*
    const anomaly = {
      userId,
      deviceId,
      anomalyType,
      voltage,
      current,
      power,
      severity,
      autoShutdown,
      timestamp: new Date(timestamp),
      createdAt: new Date()
    };

    await db.collection('anomalies').insertOne(anomaly);

    // Send notification to user
    const notificationService = require('../services/notificationService');
    await notificationService.sendAnomalyAlert(userId, {
      type: anomalyType,
      severity,
      message: `⚠️ ${anomalyType} detected! Severity: ${severity}%`
    });
    */

    res.json({
      success: true,
      message: 'Anomaly logged successfully',
      alert: {
        type: anomalyType,
        severity,
        autoShutdown
      }
    });

    // TODO: Emit to user via Socket.IO
    // io.to(userId).emit('anomalyAlert', { anomalyType, severity });

  } catch (error) {
    console.error('❌ Error logging anomaly:', error);
    res.status(500).json({ error: error.message });
  }
});

// ================= RELAY STATE CHANGE LOGGING =================
/**
 * POST /api/relay/state-change
 * Logs relay state changes to database
 */
router.post('/relay/state-change', async (req, res) => {
  try {
    const {
      userId,
      deviceId,
      relayNumber,
      state,
      timestamp
    } = req.body;

    if (!userId || !deviceId) {
      return res.status(400).json({ error: 'userId and deviceId required' });
    }

    console.log(`🔌 Relay State Change from ${deviceId} [User: ${userId}]`);
    console.log(`   Relay ${relayNumber}: ${state}`);

    // TODO: Save relay state change to database
    /*
    const relayLog = {
      userId,
      deviceId,
      relayNumber,
      state,
      timestamp: new Date(timestamp),
      createdAt: new Date()
    };

    await db.collection('relayLogs').insertOne(relayLog);
    */

    res.json({
      success: true,
      message: 'Relay state change logged',
      relay: {
        number: relayNumber,
        state: state
      }
    });

  } catch (error) {
    console.error('❌ Error logging relay state:', error);
    res.status(500).json({ error: error.message });
  }
});

// ================= GET USER'S SENSOR HISTORY =================
/**
 * GET /api/sensor-data/history/:userId
 * Retrieve sensor history for a specific user
 */
router.get('/sensor-data/history/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 100, days = 7 } = req.query;

    console.log(`📋 Fetching sensor history for user: ${userId}`);

    // TODO: Query from database
    /*
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - days);

    const sensorData = await db.collection('sensorLogs')
      .find({
        userId,
        timestamp: { $gte: startDate }
      })
      .sort({ timestamp: -1 })
      .limit(parseInt(limit))
      .toArray();

    res.json({
      success: true,
      count: sensorData.length,
      data: sensorData
    });
    */

    // Placeholder response
    res.json({
      success: true,
      count: 0,
      message: 'No sensor data available yet',
      data: []
    });

  } catch (error) {
    console.error('❌ Error fetching sensor history:', error);
    res.status(500).json({ error: error.message });
  }
});

// ================= GET USER'S ENERGY SUMMARY =================
/**
 * GET /api/energy/summary/:userId
 * Get energy consumption summary for today/this month
 */
router.get('/energy/summary/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    console.log(`📊 Fetching energy summary for user: ${userId}`);

    // TODO: Calculate from database
    /*
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const monthStart = new Date();
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);

    // Get latest sensor reading
    const latestSensor = await db.collection('sensorLogs')
      .findOne({ userId }, { sort: { timestamp: -1 } });

    // Calculate daily energy
    const dailySensors = await db.collection('sensorLogs')
      .find({ userId, timestamp: { $gte: today } })
      .toArray();

    // Calculate monthly energy
    const monthlySensors = await db.collection('sensorLogs')
      .find({ userId, timestamp: { $gte: monthStart } })
      .toArray();

    res.json({
      success: true,
      currentPower: latestSensor?.power || 0,
      dailyEnergy: latestSensor?.dailyEnergy || 0,
      monthlyEnergy: latestSensor?.monthlyEnergy || 0,
      estimatedMonthlyCost: (latestSensor?.monthlyEnergy || 0) * 7.5  // ₹7.50 per kWh in India
    });
    */

    // Placeholder response
    res.json({
      success: true,
      currentPower: 0,
      dailyEnergy: 0,
      monthlyEnergy: 0,
      estimatedMonthlyCost: 0,
      message: 'Waiting for first sensor reading'
    });

  } catch (error) {
    console.error('❌ Error fetching energy summary:', error);
    res.status(500).json({ error: error.message });
  }
});

// ================= GET ANOMALIES FOR USER =================
/**
 * GET /api/anomalies/:userId
 * Retrieve anomaly history for a user
 */
router.get('/anomalies/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 50, days = 30 } = req.query;

    console.log(`🚨 Fetching anomalies for user: ${userId}`);

    // TODO: Query from database
    /*
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - days);

    const anomalies = await db.collection('anomalies')
      .find({
        userId,
        timestamp: { $gte: startDate }
      })
      .sort({ timestamp: -1 })
      .limit(parseInt(limit))
      .toArray();

    res.json({
      success: true,
      count: anomalies.length,
      data: anomalies
    });
    */

    // Placeholder response
    res.json({
      success: true,
      count: 0,
      data: []
    });

  } catch (error) {
    console.error('❌ Error fetching anomalies:', error);
    res.status(500).json({ error: error.message });
  }
});

module.exports = router;
