// 🔌 Device Routes
// API endpoints for device control and management

const express = require('express');
const router = express.Router();
const DeviceConfigService = require('../services/deviceConfigService');
const ESP32StorageService = require('../services/esp32StorageService');

// ============ MIDDLEWARE: Validate User ID ============
const validateUserId = (req, res, next) => {
  // Extract userId from multiple sources
  const userId = req.body?.userId || req.params?.userId || req.query?.userId || req.headers?.['x-user-id'];

  if (!userId) {
    return res.status(400).json({
      success: false,
      error: 'User ID is required in URL params, request body, query, or x-user-id header'
    });
  }

  // Attach userId to request for use in route handlers
  req.userId = userId;
  next();
};

router.use(validateUserId);

// ============ GET DEVICE CONFIGURATION ============
router.get('/config/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const config = await DeviceConfigService.getDeviceConfig(userId);
    const relayStatus = await DeviceConfigService.getAllRelayStatus(userId);

    res.json({
      success: true,
      config,
      relayStatus
    });
  } catch (error) {
    console.error('❌ Error fetching device config:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to fetch device configuration'
    });
  }
});

// ============ UPDATE DEVICE NAMES ============
router.put('/config', async (req, res) => {
  try {
    const { userId, relay1Name, relay2Name } = req.body;

    if (!relay1Name || !relay2Name) {
      return res.status(400).json({
        success: false,
        error: 'Device names are required'
      });
    }

    const updated = await DeviceConfigService.updateDeviceNames(
      userId,
      relay1Name,
      relay2Name
    );

    res.json({
      success: true,
      config: updated
    });
  } catch (error) {
    console.error('❌ Error updating device config:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to update device configuration'
    });
  }
});

// ============ GET ALL RELAY STATUS ============
router.get('/relay/status/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const relayStatus = await DeviceConfigService.getAllRelayStatus(userId);

    res.json({
      success: true,
      relayStatus
    });
  } catch (error) {
    console.error('❌ Error fetching relay status:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to fetch relay status'
    });
  }
});

// ============ GET SPECIFIC RELAY STATUS ============
router.get('/relay/status/:userId/:relayNumber', async (req, res) => {
  try {
    const { userId, relayNumber } = req.params;

    const relayStatus = await DeviceConfigService.getRelayStatus(userId, parseInt(relayNumber));

    res.json({
      success: true,
      relayStatus
    });
  } catch (error) {
    console.error('❌ Error fetching relay status:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to fetch relay status'
    });
  }
});

// ============ TOGGLE RELAY ============
router.post('/relay/toggle', async (req, res) => {
  try {
    const axios = require('axios');
    const { userId, relayNumber } = req.body;

    if (!relayNumber) {
      return res.status(400).json({
        success: false,
        error: 'Relay number is required'
      });
    }

    if (![1, 2].includes(parseInt(relayNumber))) {
      return res.status(400).json({
        success: false,
        error: 'Relay number must be 1 or 2'
      });
    }

    // Get current status to know what to toggle to
    const currentStatus = await DeviceConfigService.getRelayStatus(userId, parseInt(relayNumber));
    const newState = !currentStatus.is_on;
    
    // Update database
    const updated = await DeviceConfigService.toggleRelay(userId, parseInt(relayNumber));

    // Send command to ESP32
    const esp32URL = newState 
      ? `http://wattbuddy.local/api/relay${relayNumber}/on`
      : `http://wattbuddy.local/api/relay${relayNumber}/off`;
    
    try {
      const esp32Response = await axios.post(esp32URL, {}, { timeout: 3000 });
      console.log(`✅ Relay ${relayNumber} command sent to ESP32:`, esp32Response.data);
    } catch (esp32Error) {
      console.error(`⚠️  ESP32 relay control failed: ${esp32Error.message}`);
      // Continue anyway - database was updated
    }

    res.json({
      success: true,
      relayStatus: updated,
      message: `Relay ${relayNumber} toggled to ${updated.is_on ? 'ON' : 'OFF'}`
    });
  } catch (error) {
    console.error('❌ Error toggling relay:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to toggle relay'
    });
  }
});

// ============ SET RELAY ON ============
router.post('/relay/on', async (req, res) => {
  try {
    const { userId, relayNumber } = req.body;

    if (!relayNumber) {
      return res.status(400).json({
        success: false,
        error: 'Relay number is required'
      });
    }

    const updated = await DeviceConfigService.setRelayState(userId, parseInt(relayNumber), true);

    res.json({
      success: true,
      relayStatus: updated,
      message: `Relay ${relayNumber} turned ON`
    });
  } catch (error) {
    console.error('❌ Error turning on relay:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to turn on relay'
    });
  }
});

// ============ SET RELAY OFF ============
router.post('/relay/off', async (req, res) => {
  try {
    const { userId, relayNumber } = req.body;

    if (!relayNumber) {
      return res.status(400).json({
        success: false,
        error: 'Relay number is required'
      });
    }

    const updated = await DeviceConfigService.setRelayState(userId, parseInt(relayNumber), false);

    res.json({
      success: true,
      relayStatus: updated,
      message: `Relay ${relayNumber} turned OFF`
    });
  } catch (error) {
    console.error('❌ Error turning off relay:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to turn off relay'
    });
  }
});

// ============ GET DEVICE CONTROL HISTORY ============
router.get('/history/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const limit = req.query.limit || 50;

    const history = await DeviceConfigService.getDeviceControlHistory(userId, parseInt(limit));

    res.json({
      success: true,
      history
    });
  } catch (error) {
    console.error('❌ Error fetching device control history:', error);
    res.status(500).json({
      success: false,
      error: error.message || 'Failed to fetch history'
    });
  }
});

module.exports = router;
