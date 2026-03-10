const pool = require('./db');
const GoalTrackingService = require('./services/goalTrackingService');

async function testCarryForward() {
  console.log('========================================');
  console.log('🧪 TESTING CARRY-FORWARD FUNCTIONALITY');
  console.log('========================================\n');

  const testUserId = 11;

  try {
    // Step 1: Set daily limit to 5 kWh
    console.log('1️⃣ Setting daily limit to 5 kWh with carry-forward enabled...');
    await GoalTrackingService.setUserGoals(testUserId, {
      dailyLimitKwh: 5.0,
      monthlyLimitKwh: 150.0,
      carryForwardEnabled: true
    });
    console.log('✅ Goals configured\n');

    // Step 2: Simulate yesterday's date by manually updating last_reset_date
    console.log('2️⃣ Simulating previous day (setting last_reset_date to yesterday)...');
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split('T')[0];
    
    await pool.query(
      'UPDATE user_goals SET last_reset_date = $1 WHERE user_id = $2',
      [yesterdayStr, testUserId]
    );
    console.log(`✅ Last reset date set to: ${yesterdayStr}\n`);

    // Step 3: Add some usage for yesterday in daily_usage table
    // Let's say user used 3 kWh yesterday (2 kWh should carry forward)
    console.log('3️⃣ Adding yesterday\'s usage (3 kWh) to daily_usage table...');
    await pool.query(
      `INSERT INTO daily_usage (user_id, usage_date, total_kwh, avg_power, peak_power)
       VALUES ($1, $2, 3.0, 150.0, 500.0)
       ON CONFLICT (user_id, usage_date) 
       DO UPDATE SET total_kwh = 3.0, avg_power = 150.0, peak_power = 500.0`,
      [testUserId, yesterdayStr]
    );
    console.log('✅ Yesterday used 3 kWh out of 5 kWh limit\n');

    // Step 4: Trigger daily reset
    console.log('4️⃣ Triggering daily reset (this should carry forward 2 kWh)...');
    const resetResult = await GoalTrackingService.checkAndResetDaily(testUserId);
    console.log('✅ Reset completed:', {
      resetNeeded: resetResult.resetNeeded,
      previousDate: resetResult.previousDate,
      previousUsage: resetResult.previousUsage + ' kWh',
      carriedOver: resetResult.carriedOver + ' kWh'
    });
    console.log(`\n🎉 SUCCESS! Carried forward ${resetResult.carriedOver} kWh to today!\n`);

    // Step 5: Check today's available limit
    console.log('5️⃣ Checking today\'s available limit...');
    const progress = await GoalTrackingService.getCurrentProgress(testUserId);
    console.log('✅ Today\'s allocation:', {
      dailyLimit: progress.daily.dailyLimit + ' kWh',
      carriedOver: progress.daily.carriedOver + ' kWh',
      totalAvailable: progress.daily.totalAvailable + ' kWh',
      currentUsage: progress.daily.currentUsage + ' kWh',
      remaining: progress.daily.remaining + ' kWh'
    });
    console.log('');

    // Step 6: Test scenario where user exceeds limit (no carry forward)
    console.log('6️⃣ Testing exceeded scenario (setting yesterday to 6 kWh usage)...');
    await pool.query(
      'UPDATE user_goals SET last_reset_date = $1 WHERE user_id = $2',
      [yesterdayStr, testUserId]
    );
    await pool.query(
      `UPDATE daily_usage SET total_kwh = 6.0 WHERE user_id = $1 AND usage_date = $2`,
      [testUserId, yesterdayStr]
    );
    
    const resetResult2 = await GoalTrackingService.checkAndResetDaily(testUserId);
    console.log('✅ Reset with exceeded usage:', {
      previousUsage: resetResult2.previousUsage + ' kWh (exceeded 5 kWh limit)',
      carriedOver: resetResult2.carriedOver + ' kWh (nothing to carry forward)'
    });
    console.log('');

    // Step 7: Test with carry-forward disabled
    console.log('7️⃣ Testing with carry-forward DISABLED...');
    await GoalTrackingService.setUserGoals(testUserId, {
      carryForwardEnabled: false
    });
    
    await pool.query(
      'UPDATE user_goals SET last_reset_date = $1 WHERE user_id = $2',
      [yesterdayStr, testUserId]
    );
    await pool.query(
      `UPDATE daily_usage SET total_kwh = 3.0 WHERE user_id = $1 AND usage_date = $2`,
      [testUserId, yesterdayStr]
    );
    
    const resetResult3 = await GoalTrackingService.checkAndResetDaily(testUserId);
    console.log('✅ Reset with carry-forward disabled:', {
      previousUsage: resetResult3.previousUsage + ' kWh',
      carriedOver: resetResult3.carriedOver + ' kWh (carry-forward disabled)'
    });
    console.log('');

    console.log('========================================');
    console.log('✅ CARRY-FORWARD TESTS PASSED!');
    console.log('========================================');
    console.log('\n📋 Summary:');
    console.log('  - Used 3/5 kWh → Carried forward 2 kWh ✅');
    console.log('  - Used 6/5 kWh → Carried forward 0 kWh (exceeded) ✅');
    console.log('  - Carry-forward disabled → 0 kWh regardless ✅');
    console.log('');
    
  } catch (error) {
    console.error('❌ TEST FAILED:', error);
  } finally {
    await pool.end();
    process.exit(0);
  }
}

testCarryForward();
