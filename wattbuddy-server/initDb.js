const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL || 'postgres://postgres:Albin@localhost:5432/wattbuddy';

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
  } catch (err) {
    console.error('❌ Error creating users table:', err);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();
