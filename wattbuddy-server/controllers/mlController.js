const { spawn } = require('child_process');
const path = require('path');
const db = require('../db');

// Execute ML engine
const executeMLEngine = (requestData) => {
  return new Promise((resolve, reject) => {
    const pythonProcess = spawn('python', [
      path.join(__dirname, '../../wattbudyy-ml/ml_engine.py'),
    ]);

    let output = '';
    let errorOutput = '';

    pythonProcess.stdin.write(JSON.stringify(requestData));
    pythonProcess.stdin.end();

    pythonProcess.stdout.on('data', (data) => {
      output += data.toString();
    });

    pythonProcess.stderr.on('data', (data) => {
      errorOutput += data.toString();
    });

    pythonProcess.on('close', (code) => {
      if (code === 0) {
        try {
          const result = JSON.parse(output);
          resolve(result);
        } catch (error) {
          reject(new Error('Failed to parse ML result'));
        }
      } else {
        reject(new Error(errorOutput || 'ML engine failed'));
      }
    });

    // Timeout after 30 seconds
    setTimeout(() => {
      pythonProcess.kill();
      reject(new Error('ML engine timeout'));
    }, 30000);
  });
};

// Analyze energy data with ML
exports.analyzeEnergy = async (req, res) => {
  const { userId, powerData, historicalData } = req.body;

  if (!powerData || !Array.isArray(powerData)) {
    return res.status(400).json({ error: 'Invalid power data' });
  }

  try {
    const result = await executeMLEngine({
      user_id: userId,
      action: 'analyze',
      power_data: powerData,
      historical_data: historicalData || [],
    });

    // Save analysis to database
    await saveAnalysis(userId, result);

    // Check if anomaly and send notification
    if (result.anomalies?.is_anomaly) {
      await sendAnomalyNotification(userId, result);
    }

    res.json({
      success: true,
      analysis: result,
      timestamp: new Date(),
    });
  } catch (error) {
    console.error('❌ ML Analysis error:', error);
    res.status(500).json({ error: error.message });
  }
};

// Detect anomalies only
exports.detectAnomalies = async (req, res) => {
  const { userId, powerData } = req.body;

  try {
    const result = await executeMLEngine({
      user_id: userId,
      action: 'detect',
      power_data: powerData,
    });

    res.json({
      success: true,
      detection: result,
      timestamp: new Date(),
    });
  } catch (error) {
    console.error('❌ Anomaly detection error:', error);
    res.status(500).json({ error: error.message });
  }
};

// Retrain model with new data
exports.retrainModel = async (req, res) => {
  const { userId, trainingData } = req.body;

  try {
    const result = await executeMLEngine({
      user_id: userId,
      action: 'train',
      training_data: trainingData,
    });

    res.json({
      success: true,
      message: 'Model retrained successfully',
    });
  } catch (error) {
    console.error('❌ Model retraining error:', error);
    res.status(500).json({ error: error.message });
  }
};

// Get energy insights
exports.getInsights = async (req, res) => {
  const { userId } = req.params;

  try {
    // Fetch user's recent energy data
    const dataResult = await db.query(
      `SELECT power_consumption, recorded_at 
       FROM energy_readings 
       WHERE user_id = $1 
       ORDER BY recorded_at DESC 
       LIMIT 30`,
      [userId]
    );

    const powerData = dataResult.rows.map(row => row.power_consumption);

    if (powerData.length === 0) {
      return res.json({
        success: true,
        insights: { message: 'Not enough data for analysis' },
      });
    }

    // Run ML analysis
    const result = await executeMLEngine({
      user_id: userId,
      action: 'analyze',
      power_data: powerData,
      historical_data: powerData,
    });

    res.json({
      success: true,
      insights: result,
    });
  } catch (error) {
    console.error('❌ Insights error:', error);
    res.status(500).json({ error: error.message });
  }
};

// Save analysis results
const saveAnalysis = async (userId, analysisResult) => {
  try {
    await db.query(
      `INSERT INTO energy_analysis (user_id, anomaly_data, suggestions, created_at)
       VALUES ($1, $2, $3, NOW())`,
      [userId, JSON.stringify(analysisResult.anomalies), JSON.stringify(analysisResult.suggestions)]
    );
  } catch (error) {
    console.error('Error saving analysis:', error);
  }
};

// Send anomaly notification
const sendAnomalyNotification = async (userId, analysisResult) => {
  try {
    const { severity, is_anomaly } = analysisResult.anomalies;
    const suggestions = analysisResult.suggestions || [];

    await db.query(
      `INSERT INTO notifications (user_id, type, title, message, severity, data, is_read)
       VALUES ($1, $2, $3, $4, $5, $6, false)`,
      [
        userId,
        'anomaly_alert',
        'Energy Anomaly Detected',
        `Unusual consumption detected (Severity: ${severity}%). Check your appliances.`,
        severity > 75 ? 'critical' : 'high',
        JSON.stringify({ suggestions, severity }),
      ]
    );

    console.log(`✅ Notification sent to user ${userId}`);
  } catch (error) {
    console.error('Error sending notification:', error);
  }
};
