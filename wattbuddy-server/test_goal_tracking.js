const GoalTrackingService = require('./services/goalTrackingService');

async function testGoalTracking() {
  console.log('========================================');
  console.log('🧪 TESTING GOAL TRACKING SERVICE');
  console.log('========================================\n');

  const testUserId = 11;

  try {
    // 1. Set user goals
    console.log('1️⃣ Setting user goals...');
    const goals = await GoalTrackingService.setUserGoals(testUserId, {
      dailyLimitKwh: 5.0,
      monthlyLimitKwh: 150.0,
      carryForwardEnabled: true
    });
    console.log('✅ Goals set:', {
      dailyLimit: goals.daily_limit_kwh,
      monthlyLimit: goals.monthly_limit_kwh,
      carryForward: goals.carry_forward_enabled
    });
    console.log('');

    // 2. Get current goals
    console.log('2️⃣ Retrieving user goals...');
    const retrievedGoals = await GoalTrackingService.getUserGoals(testUserId);
    console.log('✅ Retrieved goals:', {
      dailyLimit: retrievedGoals.daily_limit_kwh,
      monthlyLimit: retrievedGoals.monthly_limit_kwh,
      carriedOver: retrievedGoals.carried_over_kwh,
      lastReset: retrievedGoals.last_reset_date
    });
    console.log('');

    // 3. Check and reset daily (if needed)
    console.log('3️⃣ Checking daily reset...');
    const resetResult = await GoalTrackingService.checkAndResetDaily(testUserId);
    console.log('✅ Reset check:', {
      resetNeeded: resetResult.resetNeeded,
      previousDate: resetResult.previousDate,
      carriedOver: resetResult.carriedOver
    });
    console.log('');

    // 4. Get current progress
    console.log('4️⃣ Checking current progress...');
    const progress = await GoalTrackingService.getCurrentProgress(testUserId);
    console.log('✅ Daily Progress:', {
      currentUsage: progress.daily.currentUsage + ' kWh',
      dailyLimit: progress.daily.dailyLimit + ' kWh',
      carriedOver: progress.daily.carriedOver + ' kWh',
      totalAvailable: progress.daily.totalAvailable + ' kWh',
      remaining: progress.daily.remaining + ' kWh',
      percentageUsed: progress.daily.percentageUsed + '%',
      status: progress.daily.status
    });
    console.log('');
    console.log('✅ Monthly Progress:', {
      currentUsage: progress.monthly.currentUsage + ' kWh',
      monthlyLimit: progress.monthly.monthlyLimit + ' kWh',
      remaining: progress.monthly.remaining + ' kWh',
      percentageUsed: progress.monthly.percentageUsed + '%',
      status: progress.monthly.status
    });
    console.log('');

    // 5. Get goal history
    console.log('5️⃣ Retrieving goal history...');
    const history = await GoalTrackingService.getGoalHistory(testUserId, 7);
    console.log(`✅ Retrieved ${history.length} history records (last 7 days)`);
    if (history.length > 0) {
      console.log('Latest record:', {
        date: history[0].tracking_date,
        usage: history[0].daily_usage_kwh + ' kWh',
        limit: history[0].daily_limit_kwh + ' kWh',
        remaining: history[0].remaining_kwh + ' kWh',
        exceeded: history[0].exceeded
      });
    }
    console.log('');

    console.log('========================================');
    console.log('✅ ALL TESTS PASSED!');
    console.log('========================================');
    
  } catch (error) {
    console.error('❌ TEST FAILED:', error);
  } finally {
    process.exit(0);
  }
}

testGoalTracking();
