-- 008_user_sessions_unique_and_privacy_checks.up.sql
-- Ensure user_sessions supports ON CONFLICT (user_id, device_id) upserts and
-- validate user_privacy_settings audience values ('everyone', 'followers', 'nobody').

-- 1. Deduplicate any existing rows before creating the composite unique constraint
DELETE FROM public.user_sessions a
USING public.user_sessions b
WHERE a.user_id = b.user_id
  AND a.device_id IS NOT DISTINCT FROM b.device_id
  AND a.device_id IS NOT NULL
  AND (
    a.last_active_at < b.last_active_at
    OR (a.last_active_at = b.last_active_at AND a.id < b.id)
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_user_sessions_user_device'
  ) THEN
    ALTER TABLE public.user_sessions
      ADD CONSTRAINT uq_user_sessions_user_device UNIQUE (user_id, device_id);
  END IF;
END $$;

-- 2. Normalize and constrain user_privacy_settings audience columns
UPDATE public.user_privacy_settings
SET
  allow_messages_from = CASE
    WHEN allow_messages_from IN ('everyone', 'followers', 'nobody') THEN allow_messages_from
    ELSE 'everyone'
  END,
  allow_mentions_from = CASE
    WHEN allow_mentions_from IN ('everyone', 'followers', 'nobody') THEN allow_mentions_from
    ELSE 'everyone'
  END,
  allow_tags_from = CASE
    WHEN allow_tags_from IN ('everyone', 'followers', 'nobody') THEN allow_tags_from
    ELSE 'everyone'
  END,
  allow_story_replies_from = CASE
    WHEN allow_story_replies_from IN ('everyone', 'followers', 'nobody') THEN allow_story_replies_from
    ELSE 'everyone'
  END;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_user_privacy_audience'
  ) THEN
    ALTER TABLE public.user_privacy_settings
      ADD CONSTRAINT chk_user_privacy_audience CHECK (
        allow_messages_from IN ('everyone', 'followers', 'nobody')
        AND allow_mentions_from IN ('everyone', 'followers', 'nobody')
        AND allow_tags_from IN ('everyone', 'followers', 'nobody')
        AND allow_story_replies_from IN ('everyone', 'followers', 'nobody')
      );
  END IF;
END $$;

