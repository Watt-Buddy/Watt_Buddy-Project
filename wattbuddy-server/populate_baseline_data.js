const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// Realistic power consumption patterns (in watts)
const POWER_PATTERNS = {
  nighttime: { min: 10, max: 30 },      // 0-6am: minimal consumption
  morning: { min: 50, max: 120 },       // 6-9am: morning activities
  midday: { min: 30, max: 80 },         // 9am-5pm: daytime baseline
  evening: { min: 80, max: 180 },       // 5-10pm: peak usage
  lateNight: { min: 20, max: 50 }       // 10pm-12am: winding down
};

function getRandomPower(hour) {
  let pattern;
  
  if (hour >= 0 && hour < 6) {
    pattern = POWER_PATTERNS.nighttime;
  } else if (hour >= 6 && hour < 9) {
    pattern = POWER_PATTERNS.morning;
  } else if (hour >= 9 && hour < 17) {
    pattern = POWER_PATTERNS.midday;
  } else if (hour >= 17 && hour < 22) {
    pattern = POWER_PATTERNS.evening;
  } else {
    pattern = POWER_PATTERNS.lateNight;
  }
  
  return Math.floor(Math.random() * (pattern.max - pattern.min + 1)) + pattern.min;
}

function getRandomRelayState() {
  // 70% chance relay1 is ON, 50% chance relay2 is ON
  return {
    relay1: Math.random() < 0.7 ? 1 : 0,
    relay2: Math.random() < 0.5 ? 1 : 0
  };
}

async function populateBaselineData() {
  try {
    console.log('Starting baseline data population...\n');
    
    // Get all users
    const usersResult = await pool.query('SELECT id, email FROM Users ORDER BY id');
    const users = usersResult.rows;
    
    console.log(`Found ${users.length} user(s) in database\n`);
    
    if (users.length === 0) {
      console.log('No users found. Please create users first.');
      return;
    }
    
    const DAYS_TO_GENERATE = 2;
    const HOURS_PER_DAY = 24;
    const now = new Date();
    
    for (const user of users) {
      console.log(`Processing user ${user.id} (${user.email})...`);
      
      let totalEnergy = 0;
      const dailyReadings = { day1: [], day2: [] };
      
      // Generate hourly readings for 2 days
      for (let day = 0; day < DAYS_TO_GENERATE; day++) {
        let dailyEnergy = 0;
        
        for (let hour = 0; hour < HOURS_PER_DAY; hour++) {
          // Calculate timestamp (going backwards from now)
          const hoursBack = (DAYS_TO_GENERATE - day - 1) * HOURS_PER_DAY + (HOURS_PER_DAY - hour - 1);
          const timestamp = new Date(now.getTime() - hoursBack * 60 * 60 * 1000);
          
          // Generate realistic power and relay states
          const power = getRandomPower(hour);
          const relays = getRandomRelayState();
          
          // Calculate energy for this hour (power * 1 hour = Wh, convert to kWh)
          const energyKwh = power / 1000;
          dailyEnergy += energyKwh;
          totalEnergy += energyKwh;
          
          // Determine dominant socket (simple logic based on relay states)
          let dominantPower = 0;
          if (relays.relay1 === 1 && relays.relay2 === 0) {
            dominantPower = 1;
          } else if (relays.relay1 === 0 && relays.relay2 === 1) {
            dominantPower = 2;
          } else if (relays.relay1 === 1 && relays.relay2 === 1) {
            dominantPower = Math.random() < 0.5 ? 1 : 2;
          }
          
          // Insert into EnergyReadings (using quoted table name and correct column names)
          await pool.query(
            `INSERT INTO "EnergyReadings" 
             (user_id, voltage, current, power, energy_consumed, timestamp, relay1, relay2, dominant_relay, dominant_power) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
            [
              user.id.toString(), // user_id is TEXT
              230 + Math.random() * 10 - 5, // Voltage: 225-235V
              power / 230, // Current = Power / Voltage
              power,
              energyKwh,
              timestamp,
              relays.relay1,
              relays.relay2,
              dominantPower,
              dominantPower > 0 ? power * 0.5 : 0 // Estimated dominant power
            ]
          );
          
          // Store for daily aggregation
          if (day === 0) {
            dailyReadings.day1.push({ energy: energyKwh, timestamp });
          } else {
            dailyReadings.day2.push({ energy: energyKwh, timestamp });
          }
        }
        
        // Aggregate into daily_usage for this day
        const dayDate = new Date(now.getTime() - (DAYS_TO_GENERATE - day - 1) * 24 * 60 * 60 * 1000);
        dayDate.setHours(0, 0, 0, 0); // Set to start of day
        
        await pool.query(
          `INSERT INTO daily_usage (user_id, usage_date, total_kwh, created_at)
           VALUES ($1, $2, $3, NOW())
           ON CONFLICT (user_id, usage_date) 
           DO UPDATE SET total_kwh = EXCLUDED.total_kwh`,
          [user.id, dayDate, dailyEnergy]
        );
        
        console.log(`  Day ${day + 1}: ${dailyEnergy.toFixed(3)} kWh (${HOURS_PER_DAY} readings)`);
      }
      
      console.log(`  Total: ${totalEnergy.toFixed(3)} kWh over ${DAYS_TO_GENERATE} days`);
      console.log(`  ✓ User ${user.id} completed\n`);
    }
    
    console.log('═══════════════════════════════════════════════════════════');
    console.log('Baseline data population complete!\n');
    
    // Verify with sample user baseline
    console.log('Verifying baseline calculation for first user...');
    const firstUser = users[0];
    
    const baselineQuery = `
      SELECT 
        AVG(total_kwh * 1000 / 24) as mean_power,
        STDDEV(total_kwh * 1000 / 24) as stddev_power,
        COUNT(*) as sample_size
      FROM daily_usage
      WHERE user_id = $1
    `;
    
    const baselineResult = await pool.query(baselineQuery, [firstUser.id]);
    const baseline = baselineResult.rows[0];
    
    const threshold = Math.max(
      parseFloat(baseline.mean_power || 0) + 2 * parseFloat(baseline.stddev_power || 0),
      150
    );
    
    console.log(`\nUser ${firstUser.id} Baseline:`);
    console.log(`  Mean Power: ${parseFloat(baseline.mean_power || 0).toFixed(2)}W`);
    console.log(`  Std Dev: ${parseFloat(baseline.stddev_power || 0).toFixed(2)}W`);
    console.log(`  Threshold: ${threshold.toFixed(2)}W`);
    console.log(`  Sample Size: ${baseline.sample_size} days`);
    console.log(`  Status: ${parseInt(baseline.sample_size) >= 2 ? '✓ Ready for pattern learning' : '✗ Need more data'}\n`);
    
  } catch (error) {
    console.error('Error populating baseline data:', error);
  } finally {
    await pool.end();
  }
}

// Run the script
populateBaselineData();
