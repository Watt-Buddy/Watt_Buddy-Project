-- Monthly Energy Snapshot Migration
-- This table stores the cumulative energy meter reading at the start of each month
-- allowing accurate month-over-month usage calculation even if ESP32 resets

CREATE TABLE IF NOT EXISTS monthly_snapshots (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_date DATE NOT NULL,
  energy_at_snapshot NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT unique_user_month UNIQUE(user_id, snapshot_date)
);

CREATE INDEX IF NOT EXISTS idx_monthly_snapshots_user_date ON monthly_snapshots(user_id, snapshot_date DESC);

-- Function to get or create month snapshot
CREATE OR REPLACE FUNCTION get_or_create_month_snapshot(p_user_id INTEGER, p_snapshot_date DATE)
RETURNS NUMERIC AS $$
DECLARE
  v_energy NUMERIC;
  v_current_total NUMERIC;
BEGIN
  -- Try to get existing snapshot
  SELECT energy_at_snapshot INTO v_energy
  FROM monthly_snapshots
  WHERE user_id = p_user_id AND snapshot_date = p_snapshot_date;
  
  IF FOUND THEN
    RETURN v_energy;
  END IF;
  
  -- Get current total energy from most recent reading
  SELECT COALESCE(MAX(energy_consumed), 0) INTO v_current_total
  FROM "EnergyReadings"
  WHERE user_id = p_user_id::text;
  
  -- Create new snapshot
  INSERT INTO monthly_snapshots (user_id, snapshot_date, energy_at_snapshot)
  VALUES (p_user_id, p_snapshot_date, v_current_total)
  ON CONFLICT (user_id, snapshot_date) DO NOTHING;
  
  RETURN v_current_total;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE monthly_snapshots IS 'Stores cumulative energy meter readings at month boundaries for accurate usage tracking';
COMMENT ON FUNCTION get_or_create_month_snapshot IS 'Gets existing snapshot or creates one with current total energy';
