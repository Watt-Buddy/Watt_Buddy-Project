const pool = require('../db');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');




// 🔐 REGISTER
exports.registerUser = async (req, res) => {
  console.log("📥 Register API hit");
  console.log("📦 Body received:", req.body);

  const { username, email, consumer_number, mobile_number, password } = req.body;

  // Validate input
  if (!username || !email || !consumer_number || !mobile_number || !password) {
    console.warn("⚠️ Missing required fields");
    return res.status(400).json({ message: 'All fields are required' });
  }

  try {
    console.log("🔍 Checking if user already exists...");
    
    // 1. Check if user already exists (with timeout)
    const userCheck = await Promise.race([
      pool.query(
        'SELECT * FROM users WHERE email = $1 OR consumer_number = $2',
        [email, consumer_number]
      ),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Database timeout while checking user')), 10000)
      )
    ]);

    if (userCheck.rows.length > 0) {
      console.warn("⚠️ User already exists:", email);
      return res.status(400).json({ message: 'User already exists' });
    }

    console.log("✅ User does not exist, proceeding with registration");

    // 2. Hash password
    console.log("🔒 Hashing password...");
    const hashedPassword = await bcrypt.hash(password, 10);

    // 3. Insert user (with timeout)
    console.log("💾 Inserting user into database...");
    await Promise.race([
      pool.query(
        'INSERT INTO users (username, email, consumer_number, mobile_number, password) VALUES ($1, $2, $3, $4, $5)',
        [username, email, consumer_number, mobile_number, hashedPassword]
      ),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Database timeout while inserting user')), 10000)
      )
    ]);

    console.log("✅ Registration successful for user:", email);
    res.status(201).json({ message: 'Registration successful' });

  } catch (err) {
    console.error("❌ Registration error:", err.message);
    console.error("   Error type:", err.code || err.type || 'Unknown');
    
    // Provide specific error messages
    if (err.message.includes('timeout')) {
      return res.status(503).json({ 
        message: 'Database connection timeout. Please check if PostgreSQL is running.' 
      });
    }
    
    if (err.code === 'ECONNREFUSED') {
      return res.status(503).json({ 
        message: 'Cannot reach database. Is PostgreSQL running at ' + (process.env.DATABASE_URL || 'localhost:5432') + '?' 
      });
    }

    res.status(500).json({ message: 'Server error: ' + err.message });
  }
};






// 🔑 LOGIN (accept username OR email)
exports.loginUser = async (req, res) => {
  const { email, password } = req.body;

  console.log("📥 Login API hit with email/username:", email);
  console.log("📥 Incoming password:", password);

  if (!email || !password) {
    return res.status(400).json({ message: 'Email/username and password required' });
  }

  try {
    console.log("⏱️ Starting database query...");
    
    // Query by email OR username with timeout
    const result = await Promise.race([
      pool.query(
        'SELECT * FROM users WHERE email=$1 OR username=$1',
        [email]
      ),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Database query timeout')), 5000)
      )
    ]);

    console.log("🔍 User search result:", result.rows.length > 0 ? "User found" : "No user found");

    if (result.rows.length === 0) {
      console.log("❌ User not found for email/username:", email);
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    const user = result.rows[0];
    console.log("🔐 Comparing password for user:", user.username);
    console.log("🔐 Stored password (first 30 chars):", user.password.substring(0, 30));
    console.log("🔐 Incoming password (first 30 chars):", password.substring(0, 30));
    console.log("🔐 Stored password length:", user.password.length);
    console.log("🔐 Incoming password length:", password.length);

    // Check if stored password is bcrypt hash (starts with $2a$, $2b$, $2y$, or $2x$)
    const isBcryptHash = /^\$2[aby]\$/.test(user.password);
    console.log("🔐 Is bcrypt hash:", isBcryptHash);

    let isMatch = false;
    
    if (isBcryptHash) {
      // Password is hashed, use bcrypt.compare
      isMatch = await bcrypt.compare(password, user.password);
      console.log("🔐 Bcrypt comparison result:", isMatch);
    } else {
      // Password is plain text (legacy), direct comparison
      isMatch = password === user.password;
      console.log("🔐 Plain text comparison result:", isMatch);
      console.log("⚠️  WARNING: Plain text password detected! User should be migrated to bcrypt.");
    }
    
    if (!isMatch) {
      console.log("❌ Password mismatch for user:", email);
      return res.status(400).json({ message: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { id: user.id, email: user.email },
      'secretkey',
      { expiresIn: '1h' }
    );

    console.log("✅ Login successful for user:", user.username);
    res.json({
      message: 'Login successful',
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        consumer_number: user.consumer_number,
        mobile_number: user.mobile_number
      }
    });

  } catch (err) {
    console.error("❌ Login error:", err);
    res.status(500).json({ message: 'Server error' });
  }
};
