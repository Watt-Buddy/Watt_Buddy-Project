const { Pool } = require('pg');
require('dotenv').config();

console.log("🔌 Database connection string:", process.env.DATABASE_URL);

// Validate that DATABASE_URL is set
if (!process.env.DATABASE_URL) {
  console.error('❌ ERROR: DATABASE_URL environment variable is not set!');
  console.error('📝 Please set DATABASE_URL in your .env file');
  console.error('   Format: postgresql://username:password@localhost:5432/wattbuddy');
  process.exit(1);
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  connectionTimeoutMillis: 10000, // 10 seconds to connect
  idleTimeoutMillis: 30000,       // 30 seconds before closing idle connections
  max: 20,                         // Maximum connections in pool
});

pool.on('error', (err) => {
  console.error('❌ Unexpected error on idle client:', err.message);
  console.error('   Stack:', err.stack);
});

pool.on('connect', () => {
  console.log('✅ Database client connected');
});

pool.on('remove', () => {
  console.log('🗑️ Database client removed from pool');
});

// Test connection on startup with timeout
console.log('⏳ Testing database connection...');
pool.query('SELECT NOW()', (err, res) => {
  if (err) {
    console.error('❌ Database connection FAILED:', err.message);
    console.error('   Make sure PostgreSQL is running at:', process.env.DATABASE_URL);
    console.error('   The server will still start but API calls will timeout.');
  } else {
    console.log('✅ Database connection successful');
    console.log('   Time on database:', res.rows[0].now);
  }
});

module.exports = pool;
