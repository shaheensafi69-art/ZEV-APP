-- Rollback Migration 015: Agora RTC calls & live columns

DROP FUNCTION IF EXISTS public.respond_call_session(uuid, text, text);
DROP FUNCTION IF EXISTS public.initiate_call_session(uuid, text, uuid);
DROP TABLE IF EXISTS public.call_sessions;

ALTER TABLE public.live_streams
  DROP COLUMN IF EXISTS agora_channel,
  DROP COLUMN IF EXISTS rtc_provider;

