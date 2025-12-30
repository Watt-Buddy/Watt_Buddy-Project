-- Add FCM token and mobile number columns to users table for push notifications
-- Run this migration against the wattbuddy database

-- Add mobile number column
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS mobile_number VARCHAR(15);

-- Add FCM token column for push notifications
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- Add notification preferences column
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS notification_preferences JSONB DEFAULT '{\"anomaly_alerts\": true, \"bill_alerts\": true, \"power_limit_alerts\": true, \"emergency_alerts\": true}'::jsonb;

-- Add index for fast FCM token lookup
CREATE INDEX IF NOT EXISTS idx_users_fcm_token ON users(fcm_token) WHERE fcm_token IS NOT NULL;

-- Add index for mobile number lookup
CREATE INDEX IF NOT EXISTS idx_users_mobile ON users(mobile_number) WHERE mobile_number IS NOT NULL;

-- Create push notification log table to track sent notifications
CREATE TABLE IF NOT EXISTS push_notification_log (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL,
  fcm_token TEXT NOT NULL,
  notification_type VARCHAR(50) NOT NULL,
  title VARCHAR(255) NOT NULL,
  body TEXT NOT NULL,
  data JSONB,
  status VARCHAR(20) DEFAULT 'sent',
  error_message TEXT,
  sent_at TIMESTAMP DEFAULT NOW(),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_push_log_user_type ON push_notification_log(user_id, notification_type, sent_at DESC);

COMMENT ON COLUMN users.mobile_number IS 'User mobile number for SMS alerts (future use)';
COMMENT ON COLUMN users.fcm_token IS 'Firebase Cloud Messaging token for push notifications';
COMMENT ON COLUMN users.notification_preferences IS 'User notification preferences (anomaly, bill, power limit alerts)';
COMMENT ON TABLE push_notification_log IS 'Log of all push notifications sent to users';
