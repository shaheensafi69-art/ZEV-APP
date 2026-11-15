-- Migration 017: Group Calling & Call Participants Table
-- Extends call_sessions to support group calls, multi-participant tracking, and participant invitations.

-- 1. Extend call_sessions with group metadata
ALTER TABLE public.call_sessions
  ADD COLUMN IF NOT EXISTS is_group boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS title text,
  ADD COLUMN IF NOT EXISTS max_participants integer NOT NULL DEFAULT 8;

-- 2. Call Participants Table
CREATE TABLE IF NOT EXISTS public.call_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_session_id uuid NOT NULL REFERENCES public.call_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'participant' CHECK (role IN ('host', 'participant')),
  status text NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'ringing', 'joined', 'left', 'declined', 'busy')),
  joined_at timestamptz,
  left_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_call_participant UNIQUE (call_session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_call_participants_call
  ON public.call_participants (call_session_id, status);

CREATE INDEX IF NOT EXISTS idx_call_participants_user
  ON public.call_participants (user_id, status, created_at DESC);

-- Enable RLS
ALTER TABLE public.call_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS call_participants_select ON public.call_participants;
CREATE POLICY call_participants_select
  ON public.call_participants
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.call_sessions cs
      WHERE cs.id = call_session_id
        AND (cs.caller_id = auth.uid() OR cs.callee_id = auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM public.call_participants cp2
      WHERE cp2.call_session_id = call_session_id AND cp2.user_id = auth.uid()
    )
    OR public.is_app_admin()
  );

DROP POLICY IF EXISTS call_participants_insert ON public.call_participants;
CREATE POLICY call_participants_insert
  ON public.call_participants
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.call_sessions cs
      WHERE cs.id = call_session_id
        AND (cs.caller_id = auth.uid() OR cs.callee_id = auth.uid())
    )
    OR public.is_app_admin()
  );

DROP POLICY IF EXISTS call_participants_update ON public.call_participants;
CREATE POLICY call_participants_update
  ON public.call_participants
  FOR UPDATE
  TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.call_sessions cs
      WHERE cs.id = call_session_id
        AND (cs.caller_id = auth.uid() OR cs.callee_id = auth.uid())
    )
    OR public.is_app_admin()
  )
  WITH CHECK (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.call_sessions cs
      WHERE cs.id = call_session_id
        AND (cs.caller_id = auth.uid() OR cs.callee_id = auth.uid())
    )
    OR public.is_app_admin()
  );

-- Add call_participants to Supabase Realtime publication
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'call_participants'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.call_participants;
  END IF;
END $$;

-- 3. Atomic RPC: Invite Participant to Active Call & Convert to Group Call
CREATE OR REPLACE FUNCTION public.invite_call_participant(
  p_call_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_call public.call_sessions%ROWTYPE;
  v_participant public.call_participants%ROWTYPE;
  v_count integer;
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

  IF v_call.status <> 'accepted' AND v_call.status <> 'ringing' THEN
    RAISE EXCEPTION 'Cannot add participants to inactive call.' USING ERRCODE = '22023';
  END IF;

  -- Verify inviter is in this call
  IF v_call.caller_id <> v_me AND v_call.callee_id <> v_me
     AND NOT EXISTS (SELECT 1 FROM public.call_participants WHERE call_session_id = p_call_id AND user_id = v_me AND status = 'joined')
     AND NOT public.is_app_admin() THEN
    RAISE EXCEPTION 'Forbidden: only call participants can invite.' USING ERRCODE = '42501';
  END IF;

  IF p_user_id = v_me OR p_user_id = v_call.caller_id OR p_user_id = v_call.callee_id THEN
    RAISE EXCEPTION 'User is already in this call.' USING ERRCODE = '22023';
  END IF;

  IF public.is_blocked_between(v_me, p_user_id) THEN
    RAISE EXCEPTION 'Cannot invite blocked user.' USING ERRCODE = '42501';
  END IF;

  -- Ensure caller and callee are seeded in call_participants if converting to group
  IF NOT v_call.is_group THEN
    UPDATE public.call_sessions
    SET is_group = true,
        title = COALESCE(title, 'Group Call'),
        updated_at = now()
    WHERE id = p_call_id;

    INSERT INTO public.call_participants (call_session_id, user_id, role, status, joined_at)
    VALUES
      (p_call_id, v_call.caller_id, 'host', 'joined', v_call.started_at),
      (p_call_id, v_call.callee_id, 'participant', CASE WHEN v_call.status = 'accepted' THEN 'joined' ELSE 'ringing' END, v_call.answered_at)
    ON CONFLICT (call_session_id, user_id) DO NOTHING;
  END IF;

  -- Add newly invited participant
  INSERT INTO public.call_participants (call_session_id, user_id, role, status)
  VALUES (p_call_id, p_user_id, 'participant', 'ringing')
  ON CONFLICT (call_session_id, user_id)
  DO UPDATE SET status = 'ringing', updated_at = now()
  RETURNING * INTO v_participant;

  RETURN to_jsonb(v_participant);
END;
$$;

-- 4. Atomic RPC: Update Participant Call Status
CREATE OR REPLACE FUNCTION public.update_participant_call_status(
  p_call_id uuid,
  p_status text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_participant public.call_participants%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  IF v_status NOT IN ('joined', 'left', 'declined', 'busy') THEN
    RAISE EXCEPTION 'Invalid participant status.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.call_participants
  SET status = v_status,
      joined_at = CASE WHEN v_status = 'joined' THEN now() ELSE joined_at END,
      left_at = CASE WHEN v_status IN ('left', 'declined', 'busy') THEN now() ELSE left_at END,
      updated_at = now()
  WHERE call_session_id = p_call_id AND user_id = v_me
  RETURNING * INTO v_participant;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Participant entry not found.' USING ERRCODE = 'P0002';
  END IF;

  RETURN to_jsonb(v_participant);
END;
$$;

GRANT SELECT, INSERT, UPDATE ON public.call_participants TO authenticated;
GRANT EXECUTE ON FUNCTION public.invite_call_participant(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_participant_call_status(uuid, text) TO authenticated;

