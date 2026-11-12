-- 001_fcm_devices_and_cleanup.down.sql
-- Reversibility script for 001_fcm_devices_and_cleanup

CREATE INDEX IF NOT EXISTS idx_user_verifications_user_id ON public.user_verifications (user_id);
CREATE INDEX IF NOT EXISTS idx_hashtags_tag ON public.hashtags (tag);
CREATE INDEX IF NOT EXISTS idx_user_follows_follower_following ON public.user_follows (follower_id, following_id);
CREATE INDEX IF NOT EXISTS idx_direct_messages_conversation ON public.direct_messages (sender_id, receiver_id);
CREATE INDEX IF NOT EXISTS idx_user_trusted_devices_lookup ON public.user_trusted_devices (user_id, device_id);
CREATE INDEX IF NOT EXISTS idx_reel_likes_reel_user ON public.reel_likes (reel_id, user_id);
CREATE INDEX IF NOT EXISTS idx_reel_views_reel_viewer ON public.reel_views (reel_id, viewer_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_push_subs_token ON public.push_subscriptions (fcm_token);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_user_verifications_user_id') THEN
    ALTER TABLE public.user_verifications ADD CONSTRAINT uq_user_verifications_user_id UNIQUE (user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_referrals_pair') THEN
    ALTER TABLE public.referrals ADD CONSTRAINT uq_referrals_pair UNIQUE (referrer_id, referee_id);
  END IF;
END $$;

ALTER TABLE public.user_notifications DROP CONSTRAINT IF EXISTS user_notifications_user_id_fkey;
ALTER TABLE public.discussion_comments DROP CONSTRAINT IF EXISTS discussion_comments_student_id_fkey;
ALTER TABLE public.discussion_likes DROP CONSTRAINT IF EXISTS discussion_likes_student_id_fkey;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS zev_fmc text,
  ADD COLUMN IF NOT EXISTS zev_fcm text;

UPDATE public.profiles
SET zev_fmc = COALESCE(zev_fmc, fcm_token),
    zev_fcm = COALESCE(zev_fcm, fcm_token)
WHERE fcm_token IS NOT NULL;

DROP TRIGGER IF EXISTS trg_user_devices_updated_at ON public.user_devices;
DROP TABLE IF EXISTS public.user_devices;

