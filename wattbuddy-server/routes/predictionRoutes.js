const express = require('express');
const router = express.Router();

// Prediction endpoints
// POST /api/predictions/bill/:userId - Get predicted next month bill
router.get('/bill/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    // Get current month usage
    const currentUsage = await getCurrentMonthUsage(userId);
    const currentBill = calculateBill(currentUsage);

    // Predict next month based on current pattern
    const predictedUsage = currentUsage * 1.05; // Conservative estimate
    const predictedBill = calculateBill(predictedUsage);

    // Determine risk level
    const percentageChange = ((predictedBill - currentBill) / currentBill) * 100;
    let riskLevel = 'Low';
    if (percentageChange > 30) riskLevel = 'High';
    else if (percentageChange > 10) riskLevel = 'Medium';

    res.json({
      success: true,
      prediction: {
        predictedBill,
        predictedUsage,
        currentBill,
        currentUsage,
        riskLevel,
        percentageChange,
        timestamp: new Date().toISOString(),
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/predictions/30days/:userId - Get 30-day consumption predictions
router.get('/30days/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const predictions = [];

    // Generate 30-day predictions
    for (let i = 0; i < 30; i++) {
      const dayUsage = await predictDayUsage(userId, i);
      predictions.push({
        day: i + 1,
        predictedDailyEnergy: dayUsage,
        timestamp: new Date(Date.now() + i * 24 * 60 * 60 * 1000).toISOString(),
      });
    }

    res.json({
      success: true,
      predictions,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/predictions/breakdown/:userId - Get bill breakdown by appliance
router.get('/breakdown/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    // Get appliance-wise usage breakdown
    const breakdown = await getApplianceBreakdown(userId);

    res.json({
      success: true,
      breakdown: {
        appliances: breakdown.appliances,
        topConsumer: breakdown.topConsumer,
        topConsumerUsage: breakdown.topConsumerUsage,
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// GET /api/predictions/recommendations/:userId - Get energy saving recommendations
router.get('/recommendations/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const recommendations = [
      'Shift AC usage to night hours (9 PM - 6 AM) for lower rates',
      'Reduce water heater temperature by 2-3 degrees',
      'Switch off appliances when not in use',
      'Use LED bulbs instead of incandescent',
      'Avoid running AC and water heater simultaneously',
      'Check for refrigerator leaks causing excess cooling',
      'Use fan instead of AC during mild weather',
      'Set AC temperature to 24°C instead of 22°C',
    ];

    // Get personalized recommendations based on usage
    const personalizedRecs = await getPersonalizedRecommendations(userId);

    res.json({
      success: true,
      recommendations: personalizedRecs.length > 0 ? personalizedRecs : recommendations,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============ HELPER FUNCTIONS ============

async function getCurrentMonthUsage(userId) {
  // Simulate getting current month usage from database
  // In production, query actual database
  return 150; // kWh (example value)
}

function calculateBill(usage) {
  // Tiered pricing structure
  const baseCharge = 50;
  const ratePerKwh = 10; // ₹ per kWh
  return (usage * ratePerKwh) + baseCharge;
}

async function predictDayUsage(userId, dayOffset) {
  // Use ML to predict usage
  // For now, return simulated data with some variation
  const baseUsage = 5.5;
  const variation = Math.sin(dayOffset / 7) * 1.5;
  return baseUsage + variation + Math.random() * 0.5;
}

async function getApplianceBreakdown(userId) {
  // Simulate appliance-wise breakdown
  return {
    appliances: [
      { name: 'AC', usage: 65, percentage: 43 },
      { name: 'Refrigerator', usage: 35, percentage: 23 },
      { name: 'Water Heater', usage: 25, percentage: 17 },
      { name: 'Lighting', usage: 15, percentage: 10 },
      { name: 'Others', usage: 10, percentage: 7 },
    ],
    topConsumer: 'AC',
    topConsumerUsage: 65,
  };
}

async function getPersonalizedRecommendations(userId) {
  // Generate recommendations based on user's specific usage patterns
  // This would involve analyzing their historical data
  return [];
}

module.exports = router;
