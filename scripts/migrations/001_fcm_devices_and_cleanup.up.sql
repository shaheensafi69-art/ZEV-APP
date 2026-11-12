-- 001_fcm_devices_and_cleanup.up.sql
-- Consolidate 3 FCM token fields (profiles.{fcm_token, zev_fmc, zev_fcm}) into
-- profiles.fcm_token + multi-device public.user_devices with zero token loss,
-- purge confirmed orphan rows, add missing FKs, and remove duplicate constraints/indexes.

-- 1. Create public.user_devices
CREATE TABLE IF NOT EXISTS public.user_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  fcm_token text,
  platform text NOT NULL DEFAULT 'android',
  device_name text,
  app_version text,
  is_active boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  token_updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_devices_user_device UNIQUE (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_user_devices_user_active
  ON public.user_devices (user_id)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_user_devices_token
  ON public.user_devices (fcm_token)
  WHERE fcm_token IS NOT NULL;

DROP TRIGGER IF EXISTS trg_user_devices_updated_at ON public.user_devices;
CREATE TRIGGER trg_user_devices_updated_at
  BEFORE UPDATE ON public.user_devices
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Explicit RLS policies in the same migration
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_devices_select_own ON public.user_devices;
CREATE POLICY user_devices_select_own ON public.user_devices
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS user_devices_insert_own ON public.user_devices;
CREATE POLICY user_devices_insert_own ON public.user_devices
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS user_devices_update_own ON public.user_devices;
CREATE POLICY user_devices_update_own ON public.user_devices
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS user_devices_delete_own ON public.user_devices;
CREATE POLICY user_devices_delete_own ON public.user_devices
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- 2. Coalesce existing FCM tokens cleanly into profiles.fcm_token BEFORE dropping legacy columns
DO $$
DECLARE
  v_legacy_profile_users int;
  v_preserved_profile_users int;
  v_missing_in_devices int;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'zev_fmc'
  ) THEN
    EXECUTE $q$
      UPDATE public.profiles
      SET fcm_token = COALESCE(
            NULLIF(BTRIM(fcm_token), ''),
            NULLIF(BTRIM(zev_fmc), ''),
            NULLIF(BTRIM(zev_fcm), '')
          ),
          updated_at = now()
      WHERE NULLIF(BTRIM(fcm_token), '') IS NULL
        AND (
          NULLIF(BTRIM(zev_fmc), '') IS NOT NULL
          OR NULLIF(BTRIM(zev_fcm), '') IS NOT NULL
        );
    $q$;
  END IF;

  -- Also pull active push_subscriptions tokens into profiles.fcm_token if still empty
  UPDATE public.profiles p
  SET fcm_token = ps.fcm_token
  FROM (
    SELECT DISTINCT ON (user_id) user_id, fcm_token
    FROM public.push_subscriptions
    WHERE is_active = true
      AND NULLIF(BTRIM(fcm_token), '') IS NOT NULL
    ORDER BY user_id, updated_at DESC NULLS LAST, created_at DESC NULLS LAST
  ) ps
  WHERE p.id = ps.user_id
    AND NULLIF(BTRIM(p.fcm_token), '') IS NULL;

  -- Seed user_devices from existing push_subscriptions
  INSERT INTO public.user_devices (
    user_id, device_id, fcm_token, platform, device_name,
    is_active, last_seen_at, token_updated_at, created_at, updated_at
  )
  SELECT
    ps.user_id,
    'ps_' || ps.id::text,
    NULLIF(BTRIM(ps.fcm_token), ''),
    COALESCE(NULLIF(BTRIM(ps.device_type), ''), 'android'),
    ps.device_name,
    COALESCE(ps.is_active, true),
    COALESCE(ps.updated_at, ps.created_at, now()),
    COALESCE(ps.updated_at, ps.created_at, now()),
    COALESCE(ps.created_at, now()),
    COALESCE(ps.updated_at, now())
  FROM public.push_subscriptions ps
  WHERE NULLIF(BTRIM(ps.fcm_token), '') IS NOT NULL
  ON CONFLICT (user_id, device_id) DO UPDATE
    SET fcm_token = EXCLUDED.fcm_token,
        is_active = EXCLUDED.is_active,
        token_updated_at = GREATEST(public.user_devices.token_updated_at, EXCLUDED.token_updated_at),
        updated_at = now();

  -- Seed user_devices for any coalesced profile tokens not yet in user_devices
  INSERT INTO public.user_devices (
    user_id, device_id, fcm_token, platform, device_name,
    is_active, last_seen_at, token_updated_at
  )
  SELECT
    p.id,
    'legacy_profile_' || left(md5(p.id::text || p.fcm_token), 12),
    BTRIM(p.fcm_token),
    'android',
    'Migrated ZEV Device',
    true,
    COALESCE(p.last_seen_at, p.updated_at, now()),
    COALESCE(p.updated_at, now())
  FROM public.profiles p
  WHERE NULLIF(BTRIM(p.fcm_token), '') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.user_devices ud
      WHERE ud.user_id = p.id
        AND ud.fcm_token = BTRIM(p.fcm_token)
    )
  ON CONFLICT (user_id, device_id) DO NOTHING;

  -- Pre-drop assertion: zero token loss guarantee
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'zev_fmc'
  ) THEN
    EXECUTE $q$
      SELECT count(*) FROM public.profiles
      WHERE NULLIF(BTRIM(fcm_token), '') IS NOT NULL
         OR NULLIF(BTRIM(zev_fmc), '') IS NOT NULL
         OR NULLIF(BTRIM(zev_fcm), '') IS NOT NULL
    $q$ INTO v_legacy_profile_users;

    SELECT count(*) INTO v_preserved_profile_users
    FROM public.profiles
    WHERE NULLIF(BTRIM(fcm_token), '') IS NOT NULL;

    IF v_preserved_profile_users < v_legacy_profile_users THEN
      RAISE EXCEPTION 'Aborting zev_fmc/zev_fcm drop: preserved (%) < legacy (%)',
        v_preserved_profile_users, v_legacy_profile_users;
    END IF;
  END IF;

  SELECT count(*) INTO v_missing_in_devices
  FROM public.profiles p
  WHERE NULLIF(BTRIM(p.fcm_token), '') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.user_devices ud
      WHERE ud.user_id = p.id AND ud.fcm_token = BTRIM(p.fcm_token)
    );

  IF v_missing_in_devices > 0 THEN
    RAISE EXCEPTION 'Aborting: % profile fcm_tokens missing in user_devices', v_missing_in_devices;
  END IF;
END $$;

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS zev_fmc,
  DROP COLUMN IF EXISTS zev_fcm;

-- 3. Purge confirmed orphan rows & enforce missing foreign keys
DELETE FROM public.discussion_likes dl
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = dl.student_id);

DELETE FROM public.discussion_comments dc
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = dc.student_id);

DELETE FROM public.user_notifications un
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = un.user_id);

UPDATE public.user_notifications un
SET sender_id = NULL
WHERE sender_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = un.sender_id);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'discussion_likes_student_id_fkey') THEN
    ALTER TABLE public.discussion_likes
      ADD CONSTRAINT discussion_likes_student_id_fkey
      FOREIGN KEY (student_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'discussion_comments_student_id_fkey') THEN
    ALTER TABLE public.discussion_comments
      ADD CONSTRAINT discussion_comments_student_id_fkey
      FOREIGN KEY (student_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_notifications_user_id_fkey') THEN
    ALTER TABLE public.user_notifications
      ADD CONSTRAINT user_notifications_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

-- 4. Drop duplicate unique constraints & redundant indexes
ALTER TABLE public.user_verifications DROP CONSTRAINT IF EXISTS uq_user_verifications_user_id;
ALTER TABLE public.referrals DROP CONSTRAINT IF EXISTS uq_referrals_pair;

DROP INDEX IF EXISTS public.idx_user_verifications_user_id;
DROP INDEX IF EXISTS public.idx_hashtags_tag;
DROP INDEX IF EXISTS public.idx_user_follows_follower_following;
DROP INDEX IF EXISTS public.idx_direct_messages_conversation;
DROP INDEX IF EXISTS public.idx_user_trusted_devices_lookup;
DROP INDEX IF EXISTS public.idx_reel_likes_reel_user;
DROP INDEX IF EXISTS public.idx_reel_views_reel_viewer;
DROP INDEX IF EXISTS public.idx_subscriptions_user_id;
DROP INDEX IF EXISTS public.idx_push_subs_token;
DROP INDEX IF EXISTS public.idx_posts_student_created;
DROP INDEX IF EXISTS public.idx_reels_user_created;
DROP INDEX IF EXISTS public.idx_comments_post;

