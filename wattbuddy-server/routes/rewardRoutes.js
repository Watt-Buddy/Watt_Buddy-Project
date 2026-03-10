const express = require('express');
const router = express.Router();
const RewardController = require('../controllers/rewardController');

/**
 * Reward System Routes
 */

// Get leaderboard
router.get('/leaderboard', RewardController.getLeaderboard);

// Get all achievements
router.get('/achievements', RewardController.getAllAchievements);

// Get points history
router.get('/history/:userId', RewardController.getPointsHistory);

// Calculate daily points (testing)
router.post('/calculate/:userId', RewardController.calculateDailyPoints);

// Get user's reward profile
router.get('/:userId', RewardController.getRewards);

module.exports = router;
