const pool = require('./db');

(async () => {
  try {
    const result = await pool.query(`
      SELECT user_id, COUNT(*), MIN(timestamp), MAX(timestamp) 
      FROM "EnergyReadings" 
      GROUP BY user_id
    `);
    console.log('Users with data in EnergyReadings:');
    console.table(result.rows);
    
    // Also check if any data exists at all
    const countResult = await pool.query('SELECT COUNT(*) FROM "EnergyReadings"');
    console.log(`\nTotal rows in EnergyReadings: ${countResult.rows[0].count}`);
    
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
})();
