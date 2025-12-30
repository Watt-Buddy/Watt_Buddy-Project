const express = require('express');
const router = express.Router();
const {
  analyzeEnergy,
  detectAnomalies,
  retrainModel,
  getInsights,
} = require('../controllers/mlController');

// Analyze energy with ML (full analysis + suggestions)
router.post('/analyze', analyzeEnergy);

// Quick anomaly detection
router.post('/detect-anomalies', detectAnomalies);

// Retrain model with new data
router.post('/retrain', retrainModel);

// Get AI insights for user
router.get('/insights/:userId', getInsights);

module.exports = router;
