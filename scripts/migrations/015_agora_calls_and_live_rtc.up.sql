-- Migration 015: Agora RTC support for Voice Calls, Video Calls & Interactive Live Streaming
-- Safe, idempotent, zero destructive operations.

-- 1. Enrich live_streams with Agora RTC metadata
ALTER TABLE public.live_streams
  ADD COLUMN IF NOT EXISTS rtc_provider text NOT NULL DEFAULT 'agora',
  ADD COLUMN IF NOT EXISTS agora_channel text;

UPDATE public.live_streams
SET agora_channel = 'zev_live_' || replace(id::text, '-', '')
WHERE agora_channel IS NULL;

CREATE INDEX IF NOT EXISTS idx_live_streams_agora_channel
  ON public.live_streams (agora_channel);

-- Update start_live_stream RPC to always assign an Agora channel name
CREATE OR REPLACE FUNCTION public.start_live_stream(
  p_title text,
  p_category text DEFAULT 'General',
  p_thumbnail_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_title text := btrim(coalesce(p_title, ''));
  v_category text := coalesce(nullif(btrim(coalesce(p_category, '')), ''), 'General');
  v_thumb text := nullif(btrim(coalesce(p_thumbnail_url, '')), '');
  v_stream public.live_streams%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = v_me
      AND (COALESCE(p.is_banned, false) = true OR COALESCE(p.account_status, 'active') <> 'active')
  ) THEN
    RAISE EXCEPTION 'Your account standing does not allow hosting live rooms.' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_title) < 2 OR char_length(v_title) > 120 THEN
    RAISE EXCEPTION 'Room title must be between 2 and 120 characters.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.live_streams
  SET status = 'ended',
      ended_at = now(),
      viewer_count = 0,
      updated_at = now()
  WHERE host_id = v_me AND status = 'live';

  INSERT INTO public.live_streams (
    host_id,
    title,
    category,
    thumbnail_url,
    status,
    rtc_provider,
    agora_channel,
    viewer_count,
    peak_viewer_count,
    started_at,
    updated_at
  )
  VALUES (
    v_me,
    v_title,
    v_category,
    v_thumb,
    'live',
    'agora',
    'zev_live_' || replace(gen_random_uuid()::text, '-', ''),
    1,
    1,
    now(),
    now()
  )
  RETURNING * INTO v_stream;

  -- Ensure agora_channel ties cleanly to stream id if preferred or unique channel
  UPDATE public.live_streams
  SET agora_channel = 'zev_live_' || replace(v_stream.id::text, '-', '')
  WHERE id = v_stream.id
  RETURNING * INTO v_stream;

  INSERT INTO public.live_viewers (stream_id, user_id, joined_at, left_at, is_active)
  VALUES (v_stream.id, v_me, now(), NULL, true)
  ON CONFLICT (stream_id, user_id)
  DO UPDATE SET is_active = true, joined_at = now(), left_at = NULL;

  RETURN to_jsonb(v_stream);
END;
$$;

-- 2. Voice & Video Call Signaling Table (public.call_sessions)
CREATE TABLE IF NOT EXISTS public.call_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  caller_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  callee_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL,
  call_type text NOT NULL CHECK (call_type IN ('voice', 'video')),
  status text NOT NULL DEFAULT 'ringing' CHECK (status IN ('ringing', 'accepted', 'rejected', 'ended', 'missed', 'busy')),
  agora_channel text NOT NULL,
  end_reason text,
  started_at timestamptz NOT NULL DEFAULT now(),
  answered_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_call_not_self CHECK (caller_id <> callee_id)
);

CREATE INDEX IF NOT EXISTS idx_call_sessions_callee_status
  ON public.call_sessions (callee_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_sessions_caller
  ON public.call_sessions (caller_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_sessions_channel
  ON public.call_sessions (agora_channel);

ALTER TABLE public.call_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS call_sessions_select_participant ON public.call_sessions;
CREATE POLICY call_sessions_select_participant
  ON public.call_sessions
  FOR SELECT
  TO authenticated
  USING (auth.uid() = caller_id OR auth.uid() = callee_id OR public.is_app_admin());

DROP POLICY IF EXISTS call_sessions_insert_caller ON public.call_sessions;
CREATE POLICY call_sessions_insert_caller
  ON public.call_sessions
  FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = caller_id
    AND caller_id <> callee_id
    AND NOT public.is_blocked_between(caller_id, callee_id)
  );

DROP POLICY IF EXISTS call_sessions_update_participant ON public.call_sessions;
CREATE POLICY call_sessions_update_participant
  ON public.call_sessions
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = caller_id OR auth.uid() = callee_id OR public.is_app_admin())
  WITH CHECK (auth.uid() = caller_id OR auth.uid() = callee_id OR public.is_app_admin());

-- Add call_sessions to Supabase Realtime publication
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'call_sessions'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_sessions;
  END IF;
END $$;

-- 3. Atomic RPCs for Voice & Video Call Lifecycle
CREATE OR REPLACE FUNCTION public.initiate_call_session(
  p_callee_id uuid,
  p_call_type text DEFAULT 'voice',
  p_conversation_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_type text := lower(btrim(coalesce(p_call_type, 'voice')));
  v_call public.call_sessions%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  IF p_callee_id IS NULL OR p_callee_id = v_me THEN
    RAISE EXCEPTION 'Invalid call recipient.' USING ERRCODE = '22023';
  END IF;

  IF v_type NOT IN ('voice', 'video') THEN
    RAISE EXCEPTION 'Call type must be voice or video.' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = v_me
      AND (COALESCE(p.is_banned, false) = true OR COALESCE(p.account_status, 'active') <> 'active')
  ) THEN
    RAISE EXCEPTION 'Your account standing does not allow placing calls.' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = p_callee_id
      AND COALESCE(p.is_banned, false) = false
      AND COALESCE(p.account_status, 'active') = 'active'
  ) THEN
    RAISE EXCEPTION 'Recipient is unavailable.' USING ERRCODE = 'P0002';
  END IF;

  IF public.is_blocked_between(v_me, p_callee_id) THEN
    RAISE EXCEPTION 'Calls are not allowed between blocked users.' USING ERRCODE = '42501';
  END IF;

  -- Expire stale ringing sessions older than 90s for either user
  UPDATE public.call_sessions
  SET status = 'missed',
      ended_at = now(),
      end_reason = 'ring_timeout',
      updated_at = now()
  WHERE status = 'ringing'
    AND started_at < now() - interval '90 seconds'
    AND (caller_id IN (v_me, p_callee_id) OR callee_id IN (v_me, p_callee_id));

  INSERT INTO public.call_sessions (
    caller_id,
    callee_id,
    conversation_id,
    call_type,
    status,
    agora_channel,
    started_at,
    updated_at
  )
  VALUES (
    v_me,
    p_callee_id,
    p_conversation_id,
    v_type,
    'ringing',
    'zev_call_' || replace(gen_random_uuid()::text, '-', ''),
    now(),
    now()
  )
  RETURNING * INTO v_call;

  RETURN to_jsonb(v_call);
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_call_session(
  p_call_id uuid,
  p_action text,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_call public.call_sessions%ROWTYPE;
  v_duration int := 0;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_call
  FROM public.call_sessions
  WHERE id = p_call_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Call session not found.' USING ERRCODE = 'P0002';
  END IF;

  IF v_call.caller_id <> v_me AND v_call.callee_id <> v_me AND NOT public.is_app_admin() THEN
    RAISE EXCEPTION 'Forbidden.' USING ERRCODE = '42501';
  END IF;

  IF v_action = 'accept' THEN
    IF v_call.callee_id <> v_me THEN
      RAISE EXCEPTION 'Only the callee can accept a ringing call.' USING ERRCODE = '42501';
    END IF;
    IF v_call.status <> 'ringing' THEN
      RETURN to_jsonb(v_call);
    END IF;
    UPDATE public.call_sessions
    SET status = 'accepted',
        answered_at = now(),
        updated_at = now()
    WHERE id = p_call_id
    RETURNING * INTO v_call;
    RETURN to_jsonb(v_call);
  ELSIF v_action IN ('reject', 'busy') THEN
    IF v_call.status IN ('ended', 'rejected', 'missed') THEN
      RETURN to_jsonb(v_call);
    END IF;
    UPDATE public.call_sessions
    SET status = CASE WHEN v_action = 'busy' THEN 'busy' ELSE 'rejected' END,
        ended_at = now(),
        end_reason = coalesce(nullif(btrim(p_reason), ''), v_action),
        updated_at = now()
    WHERE id = p_call_id
    RETURNING * INTO v_call;
    RETURN to_jsonb(v_call);
  ELSIF v_action IN ('cancel', 'missed', 'end') THEN
    IF v_call.status IN ('ended', 'rejected', 'missed', 'busy') THEN
      RETURN to_jsonb(v_call);
    END IF;
    IF v_call.answered_at IS NOT NULL THEN
      v_duration := GREATEST(0, floor(extract(epoch FROM (now() - v_call.answered_at)))::int);
    END IF;
    UPDATE public.call_sessions
    SET status = CASE
          WHEN v_call.status = 'ringing' AND v_action IN ('cancel', 'missed') THEN 'missed'
          ELSE 'ended'
        END,
        ended_at = now(),
        duration_seconds = v_duration,
        end_reason = coalesce(nullif(btrim(p_reason), ''), v_action),
        updated_at = now()
    WHERE id = p_call_id
    RETURNING * INTO v_call;
    RETURN to_jsonb(v_call);
  ELSE
    RAISE EXCEPTION 'Invalid call action.' USING ERRCODE = '22023';
  END IF;
END;
$$;

GRANT SELECT, INSERT, UPDATE ON public.call_sessions TO authenticated;
GRANT EXECUTE ON FUNCTION public.initiate_call_session(uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_call_session(uuid, text, text) TO authenticated;
