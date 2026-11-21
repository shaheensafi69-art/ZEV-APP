-- Migration 022: Call notifications and incoming call reliability
-- Ensures incoming calls record in user_notifications for Realtime dispatch,
-- and transitions cleanly to 'Missed Call' upon timeout or cancellation.

CREATE OR REPLACE FUNCTION public.initiate_call_session(
  p_callee_id uuid,
  p_call_type text DEFAULT 'voice'::text,
  p_conversation_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_type text := lower(btrim(coalesce(p_call_type, 'voice')));
  v_call public.call_sessions%ROWTYPE;
  v_caller_name text;
  v_call_label text;
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

  -- Resolve caller display name for notification
  SELECT COALESCE(
    NULLIF(btrim(COALESCE(first_name, '') || ' ' || COALESCE(last_name, '')), ''),
    NULLIF(btrim(username), ''),
    'A ZEV user'
  )
  INTO v_caller_name
  FROM public.profiles
  WHERE id = v_me;

  v_call_label := CASE WHEN v_type = 'video' THEN 'Video Call' ELSE 'Voice Call' END;

  -- Record notification entry so in-app & Realtime listeners pick up the incoming call
  INSERT INTO public.user_notifications (
    user_id,
    sender_id,
    title,
    message,
    notification_type,
    link_url,
    is_read,
    app_source,
    created_at
  ) VALUES (
    p_callee_id,
    v_me,
    v_caller_name || ' • ' || v_call_label,
    'Incoming ' || v_call_label || ' on ZEV',
    CASE WHEN v_type = 'video' THEN 'video_call' ELSE 'voice_call' END,
    '/call/' || v_call.id::text,
    false,
    'zev',
    now()
  );

  RETURN to_jsonb(v_call);
END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_call_session(
  p_call_id uuid,
  p_action text,
  p_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_call public.call_sessions%ROWTYPE;
  v_duration int := 0;
  v_call_label text;
  v_caller_name text;
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

    -- Mark notification read when accepted
    UPDATE public.user_notifications
    SET is_read = true, updated_at = now()
    WHERE link_url = '/call/' || p_call_id::text
      AND user_id = v_me;

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

    -- Mark notification read when explicitly rejected
    UPDATE public.user_notifications
    SET is_read = true, updated_at = now()
    WHERE link_url = '/call/' || p_call_id::text
      AND user_id = v_call.callee_id;

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

    -- If caller canceled or ring timed out before answer, update notification to "Missed Call"
    IF v_call.answered_at IS NULL THEN
      SELECT COALESCE(
        NULLIF(btrim(COALESCE(first_name, '') || ' ' || COALESCE(last_name, '')), ''),
        NULLIF(btrim(username), ''),
        'A ZEV user'
      )
      INTO v_caller_name
      FROM public.profiles
      WHERE id = v_call.caller_id;

      v_call_label := CASE WHEN v_call.call_type = 'video' THEN 'Video Call' ELSE 'Voice Call' END;

      UPDATE public.user_notifications
      SET title = v_caller_name || ' • Missed ' || v_call_label,
          message = 'Missed ' || v_call_label || ' on ZEV',
          notification_type = 'missed_call',
          updated_at = now()
      WHERE link_url = '/call/' || p_call_id::text
        AND user_id = v_call.callee_id;
    END IF;

    RETURN to_jsonb(v_call);
  ELSE
    RAISE EXCEPTION 'Invalid call action.' USING ERRCODE = '22023';
  END IF;
END;
$function$;
