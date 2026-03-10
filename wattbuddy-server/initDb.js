const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL || 'postgres://postgres:anooja24@localhost:5432/wattbuddy';

const pool = new Pool({ connectionString });

(async () => {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        username VARCHAR(100) NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        consumer_number VARCHAR(100) UNIQUE NOT NULL,
        mobile_number VARCHAR(15),
        password TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
      );
    `);
    console.log('✅ users table created (or already exists)');
    // Create energy readings tables used by different services
    await pool.query(`
      CREATE TABLE IF NOT EXISTS "EnergyReadings" (
        id SERIAL PRIMARY KEY,
        user_id TEXT NOT NULL,
        voltage NUMERIC,
        current NUMERIC,
        power NUMERIC,
        energy_consumed NUMERIC,
        relay1 INTEGER,
        relay2 INTEGER,
        dominant_relay INTEGER,
        dominant_power NUMERIC,
        timestamp TIMESTAMP WITH TIME ZONE DEFAULT now()
      );
    `);
    console.log('✅ "EnergyReadings" table created (or already exists)');

    // Legacy / alternative snake_case table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS energy_readings (
        id SERIAL PRIMARY KEY,
        user_id TEXT NOT NULL,
        power_consumption NUMERIC,
        voltage NUMERIC,
        current NUMERIC,
        energy NUMERIC,
        power_factor NUMERIC,
        frequency NUMERIC,
        temperature NUMERIC,
        recorded_at TIMESTAMP WITH TIME ZONE DEFAULT now()
      );
    `);
    console.log('✅ energy_readings table created (or already exists)');

    // UserStats table used by server for aggregates
    await pool.query(`
      CREATE TABLE IF NOT EXISTS "UserStats" (
        user_id TEXT PRIMARY KEY,
        total_energy NUMERIC DEFAULT 0,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
      );
    `);
    console.log('✅ "UserStats" table created (or already exists)');

    // Daily usage tracking for analytics and ML
    await pool.query(`
      CREATE TABLE IF NOT EXISTS daily_usage (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL,
        usage_date DATE,
        total_kwh FLOAT DEFAULT 0,
        avg_power FLOAT DEFAULT 0,
        peak_power FLOAT DEFAULT 0,
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(user_id, usage_date)
      );
    `);
    console.log('✅ daily_usage table created (or already exists)');

    // Create indexes for performance
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_daily_usage_user_date
        ON daily_usage(user_id, usage_date DESC);
    `);
    console.log('✅ daily_usage indexes created (or already exist)');

    // User goals table for daily/monthly limits with carry-forward
    await pool.query(`
      CREATE TABLE IF NOT EXISTS user_goals (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL UNIQUE,
        daily_limit_kwh FLOAT DEFAULT 10.0,
        monthly_limit_kwh FLOAT DEFAULT 300.0,
        carry_forward_enabled BOOLEAN DEFAULT true,
        carried_over_kwh FLOAT DEFAULT 0,
        last_reset_date DATE DEFAULT CURRENT_DATE,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW(),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    `);
    console.log('✅ user_goals table created (or already exists)');

    // Goal tracking history for analytics
    await pool.query(`
      CREATE TABLE IF NOT EXISTS goal_tracking (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL,
        tracking_date DATE NOT NULL,
        daily_usage_kwh FLOAT DEFAULT 0,
        daily_limit_kwh FLOAT DEFAULT 0,
        carried_over_kwh FLOAT DEFAULT 0,
        total_available_kwh FLOAT DEFAULT 0,
        remaining_kwh FLOAT DEFAULT 0,
        exceeded BOOLEAN DEFAULT false,
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(user_id, tracking_date)
      );
    `);
    console.log('✅ goal_tracking table created (or already exists)');

    // Create indexes for goal tables
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_user_goals_user_id
        ON user_goals(user_id);
      CREATE INDEX IF NOT EXISTS idx_goal_tracking_user_date
        ON goal_tracking(user_id, tracking_date DESC);
    `);
    console.log('✅ goal tables indexes created (or already exist)');

    // User rewards and points system
    await pool.query(`
      CREATE TABLE IF NOT EXISTS user_rewards (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL UNIQUE,
        total_points INT DEFAULT 0,
        tier VARCHAR(50) DEFAULT 'Bronze',
        streak_days INT DEFAULT 0,
        last_streak_date DATE,
        achievements_unlocked INT DEFAULT 0,
        rank INT,
        created_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW(),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      );
    `);
    console.log('✅ user_rewards table created (or already exists)');

    // Achievement definitions and user achievements
    await pool.query(`
      CREATE TABLE IF NOT EXISTS achievements (
        id SERIAL PRIMARY KEY,
        achievement_key VARCHAR(100) UNIQUE NOT NULL,
        name VARCHAR(255) NOT NULL,
        description TEXT NOT NULL,
        icon VARCHAR(50),
        points_reward INT DEFAULT 10,
        tier_requirement VARCHAR(50) DEFAULT 'Bronze',
        created_at TIMESTAMP DEFAULT NOW()
      );
    `);
    console.log('✅ achievements table created (or already exist)');

    // User achievements tracking
    await pool.query(`
      CREATE TABLE IF NOT EXISTS user_achievements (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL,
        achievement_id INT NOT NULL,
        unlocked_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(user_id, achievement_id),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (achievement_id) REFERENCES achievements(id) ON DELETE CASCADE
      );
    `);
    console.log('✅ user_achievements table created (or already exists)');

    // Daily points tracking for analytics
    await pool.query(`
      CREATE TABLE IF NOT EXISTS daily_points (
        id SERIAL PRIMARY KEY,
        user_id INT NOT NULL,
        points_date DATE NOT NULL,
        points_earned INT DEFAULT 0,
        reason VARCHAR(255),
        created_at TIMESTAMP DEFAULT NOW(),
        UNIQUE(user_id, points_date)
      );
    `);
    console.log('✅ daily_points table created (or already exists)');

    // Create indexes for reward tables
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_user_rewards_user_id
        ON user_rewards(user_id);
      CREATE INDEX IF NOT EXISTS idx_user_rewards_tier
        ON user_rewards(tier);
      CREATE INDEX IF NOT EXISTS idx_user_achievements_user_id
        ON user_achievements(user_id);
      CREATE INDEX IF NOT EXISTS idx_daily_points_user_date
        ON daily_points(user_id, points_date DESC);
    `);
    console.log('✅ reward tables indexes created (or already exist)');

    // Insert default achievements
    await pool.query(`
      INSERT INTO achievements (achievement_key, name, description, points_reward, tier_requirement) VALUES
      ('first_day_under', 'First Day Under Limit', 'Stay under daily limit for the first time', 5, 'Bronze') ON CONFLICT DO NOTHING;
      INSERT INTO achievements (achievement_key, name, description, points_reward, tier_requirement) VALUES
      ('streak_7', '7-Day Streak', 'Stay under limit for 7 consecutive days', 50, 'Silver') ON CONFLICT DO NOTHING;
      INSERT INTO achievements (achievement_key, name, description, points_reward, tier_requirement) VALUES
      ('streak_30', '30-Day Streak', 'Stay under limit for 30 consecutive days', 200, 'Gold') ON CONFLICT DO NOTHING;
      INSERT INTO achievements (achievement_key, name, description, points_reward, tier_requirement) VALUES
      ('streak_100', '100-Day Streak', 'Stay under limit for 100 consecutive days', 500, 'Platinum') ON CONFLICT DO NOTHING;
      INSERT INTO achievements (achievement_key, name, description, points_reward, tier_requirement) VALUES
      ('efficiency_50', '50% Efficiency', 'Use only 50% of daily limit', 25, 'Bronze') ON CONFLICT DO NOTHING;
      INSERT INTO achievements (achievement_key, name, description, points_reward, tier_requirement) VALUES
      ('efficiency_30', '30% Efficiency', 'Use only 30% of daily limit', 75, 'Silver') ON CONFLICT DO NOTHING;
      INSERT INTO achievements (achievement_key, name, description, points_reward, tier_requirement) VALUES
      ('save_energy', 'Energy Saver', 'Earn 100 points in a single week', 100, 'Gold') ON CONFLICT DO NOTHING;
      INSERT INTO achievements (achievement_key, name, description, points_reward, tier_requirement) VALUES
      ('power_user', 'Power User', 'Maintain consistent usage patterns', 50, 'Silver') ON CONFLICT DO NOTHING;
    `);
    console.log('✅ default achievements created (or already exist)');


  } catch (err) {
    console.error('❌ Error creating users table:', err);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
