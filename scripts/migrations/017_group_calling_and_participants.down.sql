-- Migration 017: Down migration
DROP FUNCTION IF EXISTS public.update_participant_call_status(uuid, text);
DROP FUNCTION IF EXISTS public.invite_call_participant(uuid, uuid);
DROP TABLE IF EXISTS public.call_participants CASCADE;
ALTER TABLE public.call_sessions
  DROP COLUMN IF EXISTS is_group,
  DROP COLUMN IF EXISTS title,
  DROP COLUMN IF EXISTS max_participants;
