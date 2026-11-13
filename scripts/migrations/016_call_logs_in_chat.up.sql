-- 016_call_logs_in_chat.up.sql
-- Automatically creates Instagram/WhatsApp-style call logs in direct_messages
-- whenever a 1:1 call session ends, is missed, rejected, or busy.

CREATE OR REPLACE FUNCTION public.format_call_duration(p_seconds integer)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_m integer;
  v_s integer;
  v_h integer;
BEGIN
  IF p_seconds IS NULL OR p_seconds <= 0 THEN
    RETURN '0s';
  END IF;
  v_h := p_seconds / 3600;
  v_m := (p_seconds % 3600) / 60;
  v_s := p_seconds % 60;
  IF v_h > 0 THEN
    RETURN v_h::text || 'h ' || v_m::text || 'm';
  ELSIF v_m > 0 THEN
    RETURN v_m::text || 'm ' || v_s::text || 's';
  ELSE
    RETURN v_s::text || 's';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_call_session_log_to_chat()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_conv_id uuid := NEW.conversation_id;
  v_dkey text;
  v_title text;
  v_is_video boolean := (NEW.call_type = 'video');
  v_dur_text text;
  v_payload jsonb;
BEGIN
  -- Only log finalized / ended call sessions
  IF NEW.status NOT IN ('ended', 'missed', 'rejected', 'busy') THEN
    RETURN NEW;
  END IF;

  -- Avoid duplicating if already logged
  IF EXISTS (
    SELECT 1 FROM public.direct_messages
    WHERE message_type = 'call_log'
      AND (attachment_url LIKE '%' || NEW.id::text || '%' OR message_text LIKE '%' || NEW.id::text || '%')
  ) THEN
    RETURN NEW;
  END IF;

  -- Ensure direct conversation exists if not already tied
  IF v_conv_id IS NULL THEN
    v_dkey := LEAST(NEW.caller_id, NEW.callee_id)::text || ':' || GREATEST(NEW.caller_id, NEW.callee_id)::text;
    INSERT INTO public.conversations (is_group, direct_key, created_by)
    VALUES (false, v_dkey, NEW.caller_id)
    ON CONFLICT (direct_key) DO NOTHING;

    SELECT id INTO v_conv_id FROM public.conversations WHERE direct_key = v_dkey;

    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    VALUES (v_conv_id, NEW.caller_id, 'member'), (v_conv_id, NEW.callee_id, 'member')
    ON CONFLICT (conversation_id, user_id) DO NOTHING;

    -- Update session with conversation_id for integrity
    UPDATE public.call_sessions
    SET conversation_id = v_conv_id
    WHERE id = NEW.id;
  END IF;

  -- Format human-readable call summary string (WhatsApp / Instagram style)
  IF NEW.status = 'missed' THEN
    v_title := CASE WHEN v_is_video THEN 'Missed video call' ELSE 'Missed audio call' END;
  ELSIF NEW.status = 'rejected' THEN
    v_title := CASE WHEN v_is_video THEN 'Declined video call' ELSE 'Declined audio call' END;
  ELSIF NEW.status = 'busy' THEN
    v_title := 'Line busy';
  ELSIF NEW.duration_seconds > 0 THEN
    v_dur_text := public.format_call_duration(NEW.duration_seconds);
    v_title := CASE WHEN v_is_video THEN 'Video call • ' || v_dur_text ELSE 'Audio call • ' || v_dur_text END;
  ELSE
    v_title := CASE WHEN v_is_video THEN 'Cancelled video call' ELSE 'Cancelled audio call' END;
  END IF;

  -- Store structured JSON in attachment_url for rich client rendering
  v_payload := jsonb_build_object(
    'call_id', NEW.id,
    'call_type', NEW.call_type,
    'status', NEW.status,
    'duration_seconds', COALESCE(NEW.duration_seconds, 0),
    'caller_id', NEW.caller_id,
    'callee_id', NEW.callee_id,
    'started_at', NEW.started_at,
    'ended_at', NEW.ended_at
  );

  INSERT INTO public.direct_messages (
    conversation_id,
    sender_id,
    receiver_id,
    message_type,
    message_text,
    attachment_url,
    attachment_type,
    created_at
  ) VALUES (
    v_conv_id,
    NEW.caller_id,
    NEW.callee_id,
    'call_log',
    v_title,
    v_payload::text,
    'call_log',
    COALESCE(NEW.ended_at, now())
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_call_session_log_to_chat ON public.call_sessions;
CREATE TRIGGER trg_call_session_log_to_chat
  AFTER UPDATE OF status ON public.call_sessions
  FOR EACH ROW
  WHEN (NEW.status IN ('ended', 'missed', 'rejected', 'busy') AND (OLD.status IS DISTINCT FROM NEW.status))
  EXECUTE FUNCTION public.trg_call_session_log_to_chat();

