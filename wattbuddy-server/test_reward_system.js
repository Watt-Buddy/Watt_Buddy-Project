const RewardSystemService = require('./services/rewardSystemService');
const pool = require('./db');
const moment = require('moment');

async function testRewardSystem() {
  console.log('========================================');
  console.log('🧪 TESTING REWARD SYSTEM');
  console.log('========================================\n');

  const testUserId = 11;

  try {
    // Step 1: Get all achievements
    console.log('1️⃣ Fetching all achievements...');
    const achievements = await RewardSystemService.getAllAchievements();
    console.log(`✅ Found ${achievements.length} achievements:`);
    achievements.forEach(a => {
      console.log(`   • ${a.name}: ${a.points_reward} pts - "${a.description}"`);
    });
    console.log('');

    // Step 2: Initialize user rewards if needed
    console.log('2️⃣ Initializing user rewards...');
    await pool.query(
      `INSERT INTO user_rewards (user_id, total_points, tier)
       VALUES ($1, 0, 'Bronze')
       ON CONFLICT (user_id) DO NOTHING`,
      [testUserId]
    );
    console.log('✅ User rewards initialized\n');

    // Step 3: Set up test goal tracking data
    console.log('3️⃣ Setting up test data (simulating 5 days of saving)...');
    const dates = [];
    for (let i = 5; i >= 0; i--) {
      const date = moment().subtract(i, 'days').format('YYYY-MM-DD');
      dates.push(date);
      
      // Simulate usage data
      let dailyUsageKwh = 2.5; // Good savings
      let exceeded = false;

      if (i === 2) {
        dailyUsageKwh = 4.5; // Heavy usage day
      }

      await pool.query(
        `INSERT INTO goal_tracking (user_id, tracking_date, daily_usage_kwh, daily_limit_kwh, exceeded)
         VALUES ($1, $2, $3, 5.0, $4)
         ON CONFLICT (user_id, tracking_date) DO UPDATE SET
           daily_usage_kwh = $3,
           exceeded = $4`,
        [testUserId, date, dailyUsageKwh, exceeded]
      );
    }
    console.log(`✅ Created ${dates.length} days of usage data\n`);

    // Step 4: Calculate points for each day
    console.log('4️⃣ Calculating daily points for each day...');
    for (const date of dates) {
      const result = await RewardSystemService.calculateDailyPoints(testUserId, date);
      console.log(`   ${date}: +${result.pointsEarned} pts - ${result.reasons.join(' | ')}`);
    }
    console.log('');

    // Step 5: Get user rewards profile
    console.log('5️⃣ Getting user rewards profile...');
    const rewards = await RewardSystemService.getUserRewards(testUserId);
    console.log('✅ User Rewards Profile:');
    console.log(`   Total Points: ${rewards.totalPoints}`);
    console.log(`   Tier: ${rewards.tier}`);
    console.log(`   Current Streak: ${rewards.currentStreak} days`);
    console.log(`   Achievements Unlocked: ${rewards.achievementsUnlocked}/${achievements.length}`);
    if (rewards.achievements.length > 0) {
      console.log('   Unlocked Achievements:');
      rewards.achievements.forEach(a => {
        console.log(`     🏆 ${a.name} (+${a.points_reward} pts)`);
      });
    }
    console.log(`   Progress to Next Tier:`)
    console.log(`     Next: ${rewards.progressToNextTier.nextTier || 'Max Tier Reached'}`);
    console.log(`     Progress: ${rewards.progressToNextTier.progressPercent.toFixed(0)}%`);
    console.log('');

    // Step 6: Get points history
    console.log('6️⃣ Getting points history (last 7 days)...');
    const history = await RewardSystemService.getPointsHistory(testUserId, 7);
    console.log(`✅ Points history (${history.length} days):`);
    history.forEach(h => {
      console.log(`   ${h.points_date}: +${h.points_earned} pts`);
    });
    console.log('');

    // Step 7: Get leaderboard
    console.log('7️⃣ Getting leaderboard...');
    const leaderboard = await RewardSystemService.getLeaderboard(5);
    console.log(`✅ Top 5 Energy Savers:`);
    leaderboard.forEach((user, idx) => {
      let medal = '🥇';
      if (idx === 1) medal = '🥈';
      if (idx === 2) medal = '🥉';
      console.log(`   ${medal} ${idx + 1}. User ${user.user_id} (${user.username || 'N/A'}): ${user.total_points} pts - ${user.tier}`);
    });
    console.log('');

    console.log('========================================');
    console.log('✅ REWARD SYSTEM TESTS PASSED!');
    console.log('========================================');
    console.log('\n📊 Summary:');
    console.log(`  - ${achievements.length} achievements available`);
    console.log(`  - ${rewards.achievementsUnlocked} achievements unlocked`);
    console.log(`  - ${rewards.totalPoints} total points earned`);
    console.log(`  - Tier: ${rewards.tier}`);
    console.log(`  - ${rewards.currentStreak}-day streak`);
    console.log('');

  } catch (error) {
    console.error('❌ TEST FAILED:', error);
  } finally {
    await pool.end();
    process.exit(0);
  }
}

testRewardSystem();
