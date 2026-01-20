-- SQL Updates for 4 Features Implementation
-- Run these commands against your wattbuddy PostgreSQL database

-- 🔔 FEATURE 1: Add user_settings table for power limit notifications
CREATE TABLE IF NOT EXISTS user_settings (
  user_id INT PRIMARY KEY,
  daily_power_limit FLOAT DEFAULT 5000,
  alert_threshold FLOAT DEFAULT 0.75,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_settings_user
  ON user_settings(user_id);

-- 🗄 FEATURE 2: Add columns to energy_readings for ESP32 data storage
ALTER TABLE energy_readings 
ADD COLUMN IF NOT EXISTS voltage FLOAT,
ADD COLUMN IF NOT EXISTS current FLOAT,
ADD COLUMN IF NOT EXISTS energy FLOAT,
ADD COLUMN IF NOT EXISTS power_factor FLOAT,
ADD COLUMN IF NOT EXISTS frequency FLOAT,
ADD COLUMN IF NOT EXISTS temperature FLOAT;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_energy_readings_user_recorded
  ON energy_readings(user_id, recorded_at DESC);

-- 📊 FEATURE 3: Realtime graph indexes (already uses energy_readings)
-- Performance indexes are already created above

-- 🧠 FEATURE 4: Add recommendations table for ML predictions
CREATE TABLE IF NOT EXISTS recommendations (
  user_id INT PRIMARY KEY,
  recommendations_data JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_recommendations_user
  ON recommendations(user_id);

-- Create indexes for anomaly detection queries
CREATE INDEX IF NOT EXISTS idx_anomaly_alerts_user_created
  ON anomaly_alerts(user_id, created_at DESC);

-- Verify all tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
