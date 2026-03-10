/**
 * Test script for Daily Analytics Service
 * 
 * Usage:
 *   node test_daily_analytics.js backfill <userId> [daysBack]
 *   node test_daily_analytics.js baseline <userId>
 *   node test_daily_analytics.js aggregate <userId>
 *   node test_daily_analytics.js history <userId>
 */

const DailyAnalyticsService = require('./services/dailyAnalyticsService');

const command = process.argv[2];
const userId = process.argv[3] || '8'; // Default user ID

async function main() {
  try {
    console.log(`\n🔍 Running: ${command} for user ${userId}\n`);

    switch (command) {
      case 'backfill':
        const daysBack = parseInt(process.argv[4]) || 90;
        console.log(`📊 Backfilling ${daysBack} days of data...`);
        const backfillResult = await DailyAnalyticsService.backfillDailyUsage(userId, daysBack);
        console.log(`✅ Backfilled ${backfillResult.length} days`);
        console.log('Sample data:', backfillResult.slice(0, 5));
        break;

      case 'baseline':
        console.log(`📈 Computing baseline statistics...`);
        const baseline = await DailyAnalyticsService.getUserBaseline(userId);
        console.log('Baseline Statistics:');
        console.log(`  Mean Power: ${baseline.mean.toFixed(2)}W`);
        console.log(`  Std Dev: ${baseline.stddev.toFixed(2)}W`);
        console.log(`  Threshold: ${baseline.threshold.toFixed(2)}W`);
        console.log(`  95th Percentile: ${baseline.p95.toFixed(2)}W`);
        console.log(`  Sample Size: ${baseline.sampleSize} days`);
        console.log(`  Range: ${baseline.min.toFixed(2)}W - ${baseline.max.toFixed(2)}W`);
        if (baseline.isDefault) {
          console.log('⚠️  Using default values (no historical data)');
        }
        break;

      case 'aggregate':
        console.log(`🔄 Aggregating today's usage...`);
        const aggregateResult = await DailyAnalyticsService.aggregateDailyUsage(userId);
        console.log('✅ Aggregation complete:', aggregateResult);
        break;

      case 'history':
        const days = parseInt(process.argv[4]) || 30;
        console.log(`📅 Fetching ${days} days of history...`);
        const history = await DailyAnalyticsService.getDailyHistory(userId, days);
        console.log(`✅ Found ${history.length} days of data`);
        console.log('Recent 5 days:');
        history.slice(-5).forEach(day => {
          console.log(`  ${day.usage_date}: ${day.total_kwh.toFixed(3)} kWh (avg: ${day.avg_power.toFixed(1)}W, peak: ${day.peak_power.toFixed(1)}W)`);
        });
        break;

      case 'detect':
        const currentPower = parseFloat(process.argv[4]) || 100;
        console.log(`🔍 Checking if ${currentPower}W is anomalous...`);
        const detection = await DailyAnalyticsService.detectPowerAnomaly(userId, currentPower);
        console.log('Detection Result:');
        console.log(`  Is Anomaly: ${detection.isAnomaly ? '🚨 YES' : '✅ NO'}`);
        console.log(`  Severity: ${detection.severity}`);
        console.log(`  Z-Score: ${detection.zScore}`);
        console.log(`  Current: ${detection.currentPower}W`);
        console.log(`  Baseline: ${detection.baseline.toFixed(2)}W`);
        console.log(`  Threshold: ${detection.threshold.toFixed(2)}W`);
        break;

      case 'month':
        console.log(`📊 Fetching current month daily usage...`);
        const monthData = await DailyAnalyticsService.getCurrentMonthDailyUsage(userId);
        console.log(`✅ Found ${monthData.length} days in current month`);
        monthData.forEach(day => {
          console.log(`  Day ${day.day}: ${day.kwh.toFixed(3)} kWh`);
        });
        break;

      default:
        console.log('❌ Unknown command. Available commands:');
        console.log('  backfill <userId> [daysBack]  - Backfill historical daily usage');
        console.log('  baseline <userId>             - Get baseline statistics');
        console.log('  aggregate <userId>            - Aggregate today\'s usage');
        console.log('  history <userId> [days]       - Get daily history');
        console.log('  detect <userId> <powerW>      - Test anomaly detection');
        console.log('  month <userId>                - Get current month daily usage');
        process.exit(1);
    }

    console.log('\n✅ Command completed successfully\n');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

main();
