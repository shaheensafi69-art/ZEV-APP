-- 008_user_sessions_unique_and_privacy_checks.down.sql
ALTER TABLE public.user_privacy_settings
  DROP CONSTRAINT IF EXISTS chk_user_privacy_audience;

ALTER TABLE public.user_sessions
  DROP CONSTRAINT IF EXISTS uq_user_sessions_user_device;

