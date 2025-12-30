-- Goal-based reward module migration
-- Run this on the `wattbuddy` database.

ALTER TABLE users
ADD COLUMN IF NOT EXISTS total_points INT NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS reward_balance NUMERIC(10,2) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS user_points (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  points_earned INT NOT NULL,
  period_type VARCHAR(20) NOT NULL,
  goal_limit_kwh NUMERIC(10,3) NOT NULL,
  actual_usage_kwh NUMERIC(10,3) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_points_user_created
  ON user_points(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS rewards (
  id SERIAL PRIMARY KEY,
  points_required INT NOT NULL UNIQUE,
  reward_value NUMERIC(10,2) NOT NULL
);

INSERT INTO rewards (points_required, reward_value)
VALUES
  (50, 20),
  (100, 50),
  (200, 100)
ON CONFLICT (points_required) DO NOTHING;

-- Existing project already uses `user_rewards` for profile/tier state,
-- so redemption history is tracked in this table to avoid collisions.
CREATE TABLE IF NOT EXISTS user_reward_redemptions (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reward_id INT NOT NULL REFERENCES rewards(id) ON DELETE CASCADE,
  redeemed_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_reward_redemptions_user_redeemed
  ON user_reward_redemptions(user_id, redeemed_at DESC);
