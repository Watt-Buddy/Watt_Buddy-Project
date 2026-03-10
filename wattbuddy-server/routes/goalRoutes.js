const express = require('express');
const router = express.Router();
const GoalController = require('../controllers/goalController');

/**
 * Goal Tracking Routes
 */

// Set or update user goals
router.post('/set', GoalController.setGoals);

// Get current progress towards goals (daily & monthly)
router.get('/progress/:userId', GoalController.getProgress);

// Get goal tracking history
router.get('/history/:userId', GoalController.getHistory);

// Force daily reset check (for testing)
router.post('/reset/:userId', GoalController.forceReset);

// Get user's current goals
router.get('/:userId', GoalController.getGoals);

module.exports = router;
