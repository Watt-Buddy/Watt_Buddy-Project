const GoalTrackingService = require('../services/goalTrackingService');

/**
 * Controller for goal tracking and management
 */
class GoalController {
  
  /**
   * Set or update user goals
   * POST /api/goals/set
   * Body: { userId, dailyLimitKwh, monthlyLimitKwh, carryForwardEnabled }
   */
  static async setGoals(req, res) {
    try {
      const { userId, dailyLimitKwh, monthlyLimitKwh, carryForwardEnabled } = req.body;
      
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }
      
      const goals = await GoalTrackingService.setUserGoals(userId, {
        dailyLimitKwh: dailyLimitKwh ? parseFloat(dailyLimitKwh) : undefined,
        monthlyLimitKwh: monthlyLimitKwh ? parseFloat(monthlyLimitKwh) : undefined,
        carryForwardEnabled: carryForwardEnabled !== undefined ? Boolean(carryForwardEnabled) : undefined
      });
      
      res.json({
        success: true,
        message: 'Goals updated successfully',
        goals
      });
    } catch (error) {
      console.error('Error setting goals:', error);
      res.status(500).json({ error: 'Failed to set goals', details: error.message });
    }
  }

  /**
   * Get user's current goals
   * GET /api/goals/:userId
   */
  static async getGoals(req, res) {
    try {
      const userId = req.params.userId;
      
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }
      
      const goals = await GoalTrackingService.getUserGoals(userId);
      
      res.json({
        success: true,
        goals
      });
    } catch (error) {
      console.error('Error getting goals:', error);
      res.status(500).json({ error: 'Failed to get goals', details: error.message });
    }
  }

  /**
   * Get current progress towards goals
   * GET /api/goals/progress/:userId
   */
  static async getProgress(req, res) {
    try {
      const userId = req.params.userId;
      
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }
      
      const progress = await GoalTrackingService.getCurrentProgress(userId);
      
      res.json({
        success: true,
        progress
      });
    } catch (error) {
      console.error('Error getting progress:', error);
      res.status(500).json({ error: 'Failed to get progress', details: error.message });
    }
  }

  /**
   * Get goal tracking history
   * GET /api/goals/history/:userId?days=30
   */
  static async getHistory(req, res) {
    try {
      const userId = req.params.userId;
      const days = parseInt(req.query.days) || 30;
      
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }
      
      const history = await GoalTrackingService.getGoalHistory(userId, days);
      
      res.json({
        success: true,
        history,
        count: history.length
      });
    } catch (error) {
      console.error('Error getting history:', error);
      res.status(500).json({ error: 'Failed to get history', details: error.message });
    }
  }

  /**
   * Force daily reset check (for testing)
   * POST /api/goals/reset/:userId
   */
  static async forceReset(req, res) {
    try {
      const userId = req.params.userId;
      
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }
      
      const resetResult = await GoalTrackingService.checkAndResetDaily(userId);
      
      res.json({
        success: true,
        resetResult
      });
    } catch (error) {
      console.error('Error forcing reset:', error);
      res.status(500).json({ error: 'Failed to force reset', details: error.message });
    }
  }
}

module.exports = GoalController;
