const express = require('express');
const GoalRewardService = require('../services/goalRewardService');

const router = express.Router();

router.post('/evaluate', async (req, res) => {
  try {
    const { userId, periodType, goalLimitKwh, actualUsageKwh } = req.body;
    const result = await GoalRewardService.evaluateAndAward({
      userId,
      periodType,
      goalLimitKwh,
      actualUsageKwh,
    });
    res.json({ success: true, ...result });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

router.get('/status/:userId', async (req, res) => {
  try {
    const result = await GoalRewardService.getRewardStatus(req.params.userId);
    res.json({ success: true, ...result });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

router.post('/redeem', async (req, res) => {
  try {
    const { userId, rewardId } = req.body;
    const result = await GoalRewardService.redeemReward(userId, rewardId);
    res.json({ success: true, ...result });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

router.post('/apply-bill-discount', async (req, res) => {
  try {
    const { userId, originalBill } = req.body;
    const result = await GoalRewardService.applyRewardToBill(userId, originalBill);
    res.json({ success: true, ...result });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

router.post('/dashboard', async (req, res) => {
  try {
    const { userId, energyGoalKwh, currentUsageKwh } = req.body;
    const dashboard = await GoalRewardService.getDashboardData({
      userId,
      energyGoalKwh,
      currentUsageKwh,
    });
    res.json({ success: true, dashboard });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

module.exports = router;
