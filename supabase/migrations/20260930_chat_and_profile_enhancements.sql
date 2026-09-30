-- ==============================================================================
-- Migration: 20260930_chat_and_profile_enhancements.sql
-- Features:
-- 1. Username column with lowercase uniqueness trigger on profiles
-- 2. Profile privacy settings (hide/show phone, dob, country, father_name)
-- 3. user_blocks table (block / unblock user)
-- 4. user_reports table (report user with reasons)
-- 5. chat_pins table (pinned chats and messages with 24h, 7d, 30d duration)
-- ==============================================================================

-- 1. Ensure profiles has username and privacy columns
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS username TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS cover_image_url TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_phone_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_dob_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_country_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_father_name_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS privacy_settings JSONB DEFAULT '{"hide_phone": false, "hide_dob": false, "hide_country": false, "hide_father_name": false}'::jsonb;

-- Unique case-insensitive index on username
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_lower_username ON profiles (LOWER(username)) WHERE username IS NOT NULL AND username <> '';

-- Trigger function to validate and enforce username uniqueness
CREATE OR REPLACE FUNCTION check_username_unique_and_format()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.username IS NOT NULL AND NEW.username <> '' THEN
    -- Normalize to lowercase and trim
    NEW.username := LOWER(TRIM(NEW.username));
    
    -- Check character format: 3-30 characters, letters, numbers, dots, underscores
    IF NOT (NEW.username ~ '^[a-z0-9_.]{3,30}$') THEN
      RAISE EXCEPTION 'Username must be 3-30 characters long and contain only letters, numbers, underscores, and dots.';
    END IF;
    
    -- Check uniqueness
    IF EXISTS (
      SELECT 1 FROM profiles 
      WHERE LOWER(username) = NEW.username 
      AND id <> NEW.id
    ) THEN
      RAISE EXCEPTION 'This username is already taken. Please choose another username.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_check_username_unique ON profiles;
CREATE TRIGGER trigger_check_username_unique
BEFORE INSERT OR UPDATE OF username ON profiles
FOR EACH ROW
EXECUTE FUNCTION check_username_unique_and_format();

-- 2. USER_BLOCKS TABLE
CREATE TABLE IF NOT EXISTS user_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON user_blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_id);

ALTER TABLE user_blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own blocks"
ON user_blocks FOR ALL
USING (auth.uid() = blocker_id)
WITH CHECK (auth.uid() = blocker_id);

-- 3. USER_REPORTS TABLE
CREATE TABLE IF NOT EXISTS user_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reported_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  details TEXT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_reports_reporter ON user_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported ON user_reports(reported_user_id);

ALTER TABLE user_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert reports"
ON user_reports FOR INSERT
WITH CHECK (auth.uid() = reporter_id);

CREATE POLICY "Users can view their own submitted reports"
ON user_reports FOR SELECT
USING (auth.uid() = reporter_id);

-- 4. CHAT_PINS TABLE (Supports 24 Hours, 7 Days, 30 Days expiration)
CREATE TABLE IF NOT EXISTS chat_pins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  peer_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message_id UUID REFERENCES direct_messages(id) ON DELETE CASCADE,
  pin_type TEXT NOT NULL DEFAULT 'thread', -- 'thread' or 'message'
  duration TEXT NOT NULL DEFAULT '24h',    -- '24h', '7d', '30d'
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chat_pins_user ON chat_pins(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_pins_peer ON chat_pins(peer_id);
CREATE INDEX IF NOT EXISTS idx_chat_pins_expires ON chat_pins(expires_at);

ALTER TABLE chat_pins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own pins"
ON chat_pins FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);
