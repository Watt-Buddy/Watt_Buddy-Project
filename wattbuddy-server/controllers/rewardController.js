const RewardSystemService = require('../services/rewardSystemService');

/**
 * Controller for reward system and achievements
 */
class RewardController {
  
  /**
   * Get user's reward profile
   * GET /api/rewards/:userId
   */
  static async getRewards(req, res) {
    try {
      const userId = req.params.userId;
      
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }
      
      const rewards = await RewardSystemService.getUserRewards(userId);
      
      res.json({
        success: true,
        rewards
      });
    } catch (error) {
      console.error('Error getting rewards:', error);
      res.status(500).json({ error: 'Failed to get rewards', details: error.message });
    }
  }

  /**
   * Get points history
   * GET /api/rewards/history/:userId?days=30
   */
  static async getPointsHistory(req, res) {
    try {
      const userId = req.params.userId;
      const days = parseInt(req.query.days) || 30;
      
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }
      
      const history = await RewardSystemService.getPointsHistory(userId, days);
      
      res.json({
        success: true,
        history,
        count: history.length
      });
    } catch (error) {
      console.error('Error getting points history:', error);
      res.status(500).json({ error: 'Failed to get points history', details: error.message });
    }
  }

  /**
   * Get leaderboard
   * GET /api/rewards/leaderboard?limit=10
   */
  static async getLeaderboard(req, res) {
    try {
      const limit = parseInt(req.query.limit) || 10;
      
      const leaderboard = await RewardSystemService.getLeaderboard(limit);
      
      res.json({
        success: true,
        leaderboard,
        count: leaderboard.length
      });
    } catch (error) {
      console.error('Error getting leaderboard:', error);
      res.status(500).json({ error: 'Failed to get leaderboard', details: error.message });
    }
  }

  /**
   * Get all achievements
   * GET /api/rewards/achievements
   */
  static async getAllAchievements(req, res) {
    try {
      const achievements = await RewardSystemService.getAllAchievements();
      
      res.json({
        success: true,
        achievements,
        count: achievements.length
      });
    } catch (error) {
      console.error('Error getting achievements:', error);
      res.status(500).json({ error: 'Failed to get achievements', details: error.message });
    }
  }

  /**
   * Manually calculate daily points (for testing)
   * POST /api/rewards/calculate/:userId?date=2026-03-05
   */
  static async calculateDailyPoints(req, res) {
    try {
      const userId = req.params.userId;
      const date = req.query.date || require('moment')().format('YYYY-MM-DD');
      
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }
      
      const result = await RewardSystemService.calculateDailyPoints(userId, date);
      
      res.json({
        success: true,
        result
      });
    } catch (error) {
      console.error('Error calculating daily points:', error);
      res.status(500).json({ error: 'Failed to calculate points', details: error.message });
    }
  }
}

module.exports = RewardController;
