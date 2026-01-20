-- Create users table for WattBuddy server
-- Run this against the `wattbuddy` database (psql or PGAdmin)

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(100) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  consumer_number VARCHAR(100) UNIQUE NOT NULL,
  password TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE IF NOT EXISTS energy_analysis (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  anomaly_data JSONB,
  suggestions JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS notifications (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  type VARCHAR(50),
  title VARCHAR(255),
  message TEXT,
  severity VARCHAR(20),
  data JSONB,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS energy_readings (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  power_consumption FLOAT,
  recorded_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS anomaly_alerts (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  anomaly_data JSONB NOT NULL,
  power_data JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_anomaly_user_created 
  ON anomaly_alerts(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_energy_analysis_user
  ON energy_analysis(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_user
  ON notifications(user_id, created_at DESC);

-- Monthly usage limits and tracking
CREATE TABLE IF NOT EXISTS monthly_limits (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL UNIQUE,
  monthly_limit_kwh FLOAT NOT NULL DEFAULT 300,
  limit_renewal_day INT DEFAULT 1,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Monthly usage tracking with carryover
CREATE TABLE IF NOT EXISTS monthly_usage (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  month_year VARCHAR(7),
  allocated_kwh FLOAT,
  consumed_kwh FLOAT DEFAULT 0,
  remaining_kwh FLOAT,
  carryover_from_previous FLOAT DEFAULT 0,
  carryover_to_next FLOAT DEFAULT 0,
  exceeded BOOLEAN DEFAULT FALSE,
  excess_amount FLOAT DEFAULT 0,
  notification_sent BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, month_year)
);

-- Daily usage tracking for better analytics
CREATE TABLE IF NOT EXISTS daily_usage (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  usage_date DATE,
  total_kwh FLOAT DEFAULT 0,
  avg_power FLOAT DEFAULT 0,
  peak_power FLOAT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, usage_date)
);

-- Usage alerts (when limit is exceeded)
CREATE TABLE IF NOT EXISTS usage_alerts (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  alert_type VARCHAR(50),
  threshold_percentage INT,
  current_usage FLOAT,
  monthly_limit FLOAT,
  message TEXT,
  is_resolved BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_monthly_usage_user_month
  ON monthly_usage(user_id, month_year DESC);

CREATE INDEX IF NOT EXISTS idx_daily_usage_user_date
  ON daily_usage(user_id, usage_date DESC);

CREATE INDEX IF NOT EXISTS idx_usage_alerts_user
  ON usage_alerts(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_monthly_limits_user
  ON monthly_limits(user_id);
