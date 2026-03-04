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
  } catch (err) {
    console.error('❌ Error creating users table:', err);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
