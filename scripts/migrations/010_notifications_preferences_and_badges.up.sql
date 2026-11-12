-- Migration 010 UP: Notification Preferences Initialization, Badge Indexes & Unread Counter RPC

BEGIN;

CREATE INDEX IF NOT EXISTS idx_user_notifications_unread_badge
  ON public.user_notifications (user_id, created_at DESC)
  WHERE is_read = false;

CREATE INDEX IF NOT EXISTS idx_follow_requests_target_pending
  ON public.follow_requests (target_id, created_at DESC)
  WHERE status = 'pending';

CREATE OR REPLACE FUNCTION public.get_unread_badge_counts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_notif_count integer := 0;
  v_msg_count integer := 0;
  v_req_count integer := 0;
BEGIN
  IF v_me IS NULL THEN
    RETURN jsonb_build_object(
      'unread_notifications', 0,
      'unread_messages', 0,
      'unread_requests', 0,
      'total_unread', 0
    );
  END IF;

  SELECT count(*)::integer INTO v_notif_count
  FROM public.user_notifications un
  WHERE un.user_id = v_me
    AND un.is_read = false
    AND lower(coalesce(un.notification_type, '')) NOT IN (
      'chat', 'message', 'direct_message', 'group_message'
    );

  SELECT count(*)::integer INTO v_msg_count
  FROM public.direct_messages dm
  LEFT JOIN public.conversation_members cm
    ON cm.conversation_id = dm.conversation_id AND cm.user_id = v_me
  WHERE dm.sender_id <> v_me
    AND dm.deleted_at IS NULL
    AND (dm.conversation_id IS NULL OR cm.user_id IS NOT NULL)
    AND (dm.receiver_id IS NULL OR dm.receiver_id = v_me)
    AND CASE
      WHEN dm.receiver_id = v_me THEN dm.is_read = false
      ELSE (cm.last_read_at IS NULL OR dm.created_at > cm.last_read_at)
    END
    AND NOT EXISTS (
      SELECT 1 FROM public.message_reads mr
      WHERE mr.message_id = dm.id AND mr.user_id = v_me
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.message_deletions md
      WHERE md.message_id = dm.id AND md.user_id = v_me
    )
    AND NOT public.is_blocked_between(v_me, dm.sender_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.message_requests mreq
      WHERE mreq.conversation_id = dm.conversation_id
        AND mreq.recipient_id = v_me
        AND mreq.status IN ('declined', 'pending')
    );

  SELECT count(*)::integer INTO v_req_count
  FROM public.message_requests mreq
  WHERE mreq.recipient_id = v_me
    AND mreq.status = 'pending'
    AND NOT public.is_blocked_between(v_me, mreq.sender_id);

  RETURN jsonb_build_object(
    'unread_notifications', coalesce(v_notif_count, 0),
    'unread_messages', coalesce(v_msg_count, 0),
    'unread_requests', coalesce(v_req_count, 0),
    'total_unread', coalesce(v_notif_count, 0) + coalesce(v_msg_count, 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_or_init_notification_preferences()
RETURNS public.notification_preferences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_row public.notification_preferences;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  INSERT INTO public.notification_preferences (user_id)
  VALUES (v_me)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_row
  FROM public.notification_preferences
  WHERE user_id = v_me;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.get_unread_badge_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_unread_badge_counts() TO authenticated;

REVOKE ALL ON FUNCTION public.get_or_init_notification_preferences() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_or_init_notification_preferences() TO authenticated;

COMMIT;
