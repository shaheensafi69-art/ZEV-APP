-- ==============================================================================
-- Migration: 20261001_indexes_push_subscriptions_and_privacy.sql
-- Features:
-- 1. High-performance composite indexes for scale:
--    - user_follows (follower_id, following_id) & (following_id, follower_id)
--    - reel_views (reel_id, viewer_id) & (viewer_id, reel_id)
--    - direct_messages (sender_id, receiver_id, created_at) & (receiver_id, sender_id, created_at)
--    - reel_likes (reel_id, user_id)
-- 2. push_subscriptions table:
--    - Multi-device FCM token management per user
--    - Clean segregation between ZEV app and Safi Academy app ('app_name')
-- 3. user_notifications app segregation:
--    - app_source column ('zev', 'safi_academy') with composite index
-- 4. profiles table privacy flags:
--    - Granular visibility toggles for all profile attributes
-- ==============================================================================

-- 1. COMPOSITE INDEXES FOR HIGH-TRAFFIC SCALABILITY
CREATE INDEX IF NOT EXISTS idx_user_follows_follower_following ON user_follows (follower_id, following_id);
CREATE INDEX IF NOT EXISTS idx_user_follows_following_follower ON user_follows (following_id, follower_id);

CREATE INDEX IF NOT EXISTS idx_reel_views_reel_viewer ON reel_views (reel_id, viewer_id);
CREATE INDEX IF NOT EXISTS idx_reel_views_viewer_reel ON reel_views (viewer_id, reel_id);

CREATE INDEX IF NOT EXISTS idx_direct_messages_sender_receiver ON direct_messages (sender_id, receiver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_direct_messages_receiver_sender ON direct_messages (receiver_id, sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_direct_messages_unread ON direct_messages (receiver_id, is_read) WHERE is_read = false;

CREATE INDEX IF NOT EXISTS idx_reel_likes_reel_user ON reel_likes (reel_id, user_id);
CREATE INDEX IF NOT EXISTS idx_reel_likes_user_reel ON reel_likes (user_id, reel_id);

-- 2. PUSH_SUBSCRIPTIONS TABLE (MULTI-DEVICE & MULTI-APP FCM SUPPORT)
CREATE TABLE IF NOT EXISTS push_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL UNIQUE,
    app_name TEXT NOT NULL DEFAULT 'zev', -- 'zev' or 'safi_academy'
    device_type TEXT,                     -- 'android', 'ios', 'web', 'desktop'
    device_name TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_push_subs_user_app ON push_subscriptions (user_id, app_name);
CREATE INDEX IF NOT EXISTS idx_push_subs_token ON push_subscriptions (fcm_token);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own push subscriptions"
ON push_subscriptions FOR ALL
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 3. USER_NOTIFICATIONS APP SEGREGATION
ALTER TABLE user_notifications ADD COLUMN IF NOT EXISTS app_source TEXT DEFAULT 'zev';
CREATE INDEX IF NOT EXISTS idx_user_notifications_user_app ON user_notifications (user_id, app_source, is_read, created_at DESC);

-- 4. EXPAND PROFILE PRIVACY COLUMNS
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_email_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_bio_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_wallet_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_score_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_referral_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_language_hidden BOOLEAN DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_role_hidden BOOLEAN DEFAULT false;

-- Update privacy_settings default JSON
ALTER TABLE profiles ALTER COLUMN privacy_settings SET DEFAULT '{
  "hide_phone": false,
  "hide_dob": false,
  "hide_country": false,
  "hide_father_name": false,
  "hide_email": false,
  "hide_bio": false,
  "hide_score": false,
  "hide_wallet": false,
  "hide_referral": false,
  "hide_language": false,
  "hide_role": false
}'::jsonb;
