-- Migration 009: Phase 4 Real-Time Chat, Notes, Groups, Requests, Privacy-Respecting Presence & Audit Trail

-- 1. Ephemeral 24-hour Inbox Notes (replaces storing notes inside profiles.bio)
CREATE TABLE IF NOT EXISTS public.user_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  content text NOT NULL CHECK (char_length(btrim(content)) BETWEEN 1 AND 80),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_user_notes_expires ON public.user_notes (expires_at DESC);

ALTER TABLE public.user_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_notes_select_active ON public.user_notes;
CREATE POLICY user_notes_select_active ON public.user_notes
  FOR SELECT TO authenticated
  USING (
    auth.uid() = user_id
    OR (expires_at > now() AND NOT public.is_blocked_between(auth.uid(), user_id))
  );

DROP POLICY IF EXISTS user_notes_manage_own ON public.user_notes;
CREATE POLICY user_notes_manage_own ON public.user_notes
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 2. Partial indexes to accelerate inbox, deleted-for-me filtering & search
CREATE INDEX IF NOT EXISTS idx_direct_messages_conv_created
  ON public.direct_messages (conversation_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_direct_messages_unread_conv
  ON public.direct_messages (conversation_id, sender_id, is_read)
  WHERE is_read = false AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_conversation_pins_user
  ON public.conversation_pins (user_id, conversation_id);

CREATE INDEX IF NOT EXISTS idx_conversation_mutes_user
  ON public.conversation_mutes (user_id, conversation_id);

CREATE INDEX IF NOT EXISTS idx_message_requests_recipient_pending
  ON public.message_requests (recipient_id, status, updated_at DESC)
  WHERE status = 'pending';

-- 3. Privacy-respecting presence RPC (honors user_privacy_settings.hide_online_status & blocks)
CREATE OR REPLACE FUNCTION public.get_profiles_presence(p_user_ids uuid[])
RETURNS TABLE (
  user_id uuid,
  is_online boolean,
  last_seen timestamptz,
  hide_online_status boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_me_hides boolean := false;
BEGIN
  IF v_me IS NOT NULL THEN
    SELECT COALESCE(ups.hide_online_status, false)
    INTO v_me_hides
    FROM public.user_privacy_settings ups
    WHERE ups.user_id = v_me;
    v_me_hides := COALESCE(v_me_hides, false);
  END IF;

  RETURN QUERY
  SELECT
    p.id AS user_id,
    CASE
      WHEN v_me IS NULL THEN false
      WHEN p.id <> v_me AND (
        v_me_hides
        OR COALESCE(ups.hide_online_status, false)
        OR public.is_blocked_between(v_me, p.id)
      ) THEN false
      ELSE COALESCE(p.is_online, false)
    END AS is_online,
    CASE
      WHEN v_me IS NULL THEN NULL::timestamptz
      WHEN p.id <> v_me AND (
        v_me_hides
        OR COALESCE(ups.hide_online_status, false)
        OR public.is_blocked_between(v_me, p.id)
      ) THEN NULL::timestamptz
      ELSE COALESCE(p.last_seen_at, p.last_seen)
    END AS last_seen,
    (v_me_hides OR COALESCE(ups.hide_online_status, false)) AS hide_online_status
  FROM public.profiles p
  LEFT JOIN public.user_privacy_settings ups ON ups.user_id = p.id
  WHERE p.id = ANY(COALESCE(p_user_ids, ARRAY[]::uuid[]));
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_profiles_presence(uuid[]) TO authenticated;

-- 4. Atomic Group Conversation Creation RPC
CREATE OR REPLACE FUNCTION public.create_group_conversation(
  p_title text,
  p_member_ids uuid[],
  p_avatar_url text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_clean_title text;
  v_conv_id uuid;
  v_uid uuid;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  v_clean_title := btrim(COALESCE(p_title, ''));
  IF char_length(v_clean_title) < 1 OR char_length(v_clean_title) > 80 THEN
    RAISE EXCEPTION 'Group name must be between 1 and 80 characters';
  END IF;

  INSERT INTO public.conversations (
    is_group,
    title,
    avatar_url,
    created_by,
    last_message_text,
    last_message_type,
    last_message_at,
    last_sender_id
  )
  VALUES (
    true,
    v_clean_title,
    NULLIF(btrim(COALESCE(p_avatar_url, '')), ''),
    v_me,
    'Group created',
    'system',
    now(),
    v_me
  )
  RETURNING id INTO v_conv_id;

  -- Add creator as admin
  INSERT INTO public.conversation_members (conversation_id, user_id, role, last_read_at)
  VALUES (v_conv_id, v_me, 'admin', now())
  ON CONFLICT (conversation_id, user_id) DO NOTHING;

  -- Add unique non-blocked members
  IF p_member_ids IS NOT NULL THEN
    FOR v_uid IN
      SELECT DISTINCT u
      FROM unnest(p_member_ids) AS u
      WHERE u IS NOT NULL AND u <> v_me
    LOOP
      IF NOT public.is_blocked_between(v_me, v_uid) THEN
        INSERT INTO public.conversation_members (conversation_id, user_id, role)
        VALUES (v_conv_id, v_uid, 'member')
        ON CONFLICT (conversation_id, user_id) DO NOTHING;

        INSERT INTO public.user_notifications (
          user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
        ) VALUES (
          v_uid,
          v_me,
          'Added to Group',
          'You were added to "' || v_clean_title || '"',
          'group_invitation',
          '/chat/' || v_conv_id::text,
          false,
          'zev',
          now()
        );
      END IF;
    END LOOP;
  END IF;

  RETURN v_conv_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_group_conversation(text, uuid[], text) TO authenticated;

-- 5. Edit & Soft Delete / Delete-For-Me / Delete-Conversation-For-Me RPCs
CREATE OR REPLACE FUNCTION public.edit_direct_message(
  p_message_id uuid,
  p_new_text text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_msg public.direct_messages%ROWTYPE;
  v_clean text := btrim(COALESCE(p_new_text, ''));
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF char_length(v_clean) < 1 OR char_length(v_clean) > 4000 THEN
    RAISE EXCEPTION 'Edited message text must be between 1 and 4000 characters';
  END IF;

  SELECT * INTO v_msg FROM public.direct_messages WHERE id = p_message_id;
  IF v_msg.id IS NULL THEN
    RAISE EXCEPTION 'Message not found';
  END IF;
  IF v_msg.sender_id <> v_me THEN
    RAISE EXCEPTION 'You can only edit your own messages';
  END IF;
  IF v_msg.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot edit a deleted message';
  END IF;

  INSERT INTO public.message_edits (message_id, editor_id, previous_text)
  VALUES (v_msg.id, v_me, v_msg.message_text);

  UPDATE public.direct_messages
  SET message_text = v_clean,
      edited_at = now()
  WHERE id = v_msg.id
  RETURNING * INTO v_msg;

  RETURN to_jsonb(v_msg);
END;
$$;

GRANT EXECUTE ON FUNCTION public.edit_direct_message(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_message_for_me(p_message_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_msg public.direct_messages%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO v_msg FROM public.direct_messages WHERE id = p_message_id;
  IF v_msg.id IS NULL THEN
    RETURN false;
  END IF;

  IF NOT (
    v_msg.sender_id = v_me
    OR v_msg.receiver_id = v_me
    OR (v_msg.conversation_id IS NOT NULL AND public.is_conversation_member(v_msg.conversation_id, v_me))
  ) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  INSERT INTO public.message_deletions (message_id, user_id)
  VALUES (p_message_id, v_me)
  ON CONFLICT (message_id, user_id) DO NOTHING;

  UPDATE public.direct_messages
  SET deleted_for_user_ids = array_append(deleted_for_user_ids, v_me)
  WHERE id = p_message_id
    AND NOT (v_me = ANY(deleted_for_user_ids));

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_message_for_me(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_message_for_everyone(p_message_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_msg public.direct_messages%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO v_msg FROM public.direct_messages WHERE id = p_message_id;
  IF v_msg.id IS NULL THEN
    RETURN false;
  END IF;
  IF v_msg.sender_id <> v_me THEN
    RAISE EXCEPTION 'Only sender can delete for everyone';
  END IF;

  UPDATE public.direct_messages
  SET deleted_at = COALESCE(deleted_at, now()),
      message_text = '',
      attachment_url = NULL,
      file_name = NULL,
      file_size = NULL,
      mime_type = NULL
  WHERE id = p_message_id;

  DELETE FROM public.message_reactions WHERE message_id = p_message_id;
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_message_for_everyone(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_conversation_for_me(p_conversation_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_cnt integer := 0;
BEGIN
  IF v_me IS NULL OR NOT public.is_conversation_member(p_conversation_id, v_me) THEN
    RETURN 0;
  END IF;

  INSERT INTO public.message_deletions (message_id, user_id)
  SELECT dm.id, v_me
  FROM public.direct_messages dm
  WHERE dm.conversation_id = p_conversation_id
    AND NOT (v_me = ANY(dm.deleted_for_user_ids))
  ON CONFLICT (message_id, user_id) DO NOTHING;

  WITH upd AS (
    UPDATE public.direct_messages
    SET deleted_for_user_ids = array_append(deleted_for_user_ids, v_me),
        is_read = CASE WHEN sender_id <> v_me THEN true ELSE is_read END,
        read_at = CASE WHEN sender_id <> v_me THEN COALESCE(read_at, now()) ELSE read_at END
    WHERE conversation_id = p_conversation_id
      AND NOT (v_me = ANY(deleted_for_user_ids))
    RETURNING id
  )
  SELECT count(*)::int INTO v_cnt FROM upd;

  UPDATE public.conversation_members
  SET last_read_at = now()
  WHERE conversation_id = p_conversation_id AND user_id = v_me;

  RETURN v_cnt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_conversation_for_me(uuid) TO authenticated;

-- 6. Message Request acceptance / decline + automatic request creation trigger
CREATE OR REPLACE FUNCTION public.respond_message_request(
  p_conversation_id uuid,
  p_action text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_norm text := lower(btrim(COALESCE(p_action, '')));
BEGIN
  IF v_me IS NULL OR v_norm NOT IN ('accept', 'accepted', 'decline', 'declined') THEN
    RETURN false;
  END IF;

  IF v_norm IN ('accept', 'accepted') THEN
    UPDATE public.message_requests
    SET status = 'accepted', updated_at = now()
    WHERE conversation_id = p_conversation_id
      AND recipient_id = v_me;
    RETURN FOUND;
  ELSE
    UPDATE public.message_requests
    SET status = 'declined', updated_at = now()
    WHERE conversation_id = p_conversation_id
      AND recipient_id = v_me;
    PERFORM public.delete_conversation_for_me(p_conversation_id);
    RETURN true;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_message_request(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.trg_direct_message_handle_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_follows boolean := false;
  v_replied_before boolean := false;
BEGIN
  IF NEW.receiver_id IS NULL OR NEW.receiver_id = NEW.sender_id OR NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- If the recipient of an existing pending request sends a reply, auto-accept the request
  UPDATE public.message_requests
  SET status = 'accepted', updated_at = now()
  WHERE conversation_id = NEW.conversation_id
    AND sender_id = NEW.receiver_id
    AND recipient_id = NEW.sender_id
    AND status = 'pending';

  -- Check if recipient already follows sender or has already sent a message in this thread
  SELECT EXISTS (
    SELECT 1 FROM public.user_follows uf
    WHERE uf.follower_id = NEW.receiver_id AND uf.following_id = NEW.sender_id
  ) INTO v_follows;

  IF NOT v_follows THEN
    SELECT EXISTS (
      SELECT 1 FROM public.direct_messages dm
      WHERE dm.conversation_id = NEW.conversation_id
        AND dm.sender_id = NEW.receiver_id
    ) INTO v_replied_before;

    IF NOT v_replied_before THEN
      INSERT INTO public.message_requests (sender_id, recipient_id, conversation_id, status)
      VALUES (NEW.sender_id, NEW.receiver_id, NEW.conversation_id, 'pending')
      ON CONFLICT (sender_id, recipient_id) DO UPDATE
      SET conversation_id = EXCLUDED.conversation_id,
          updated_at = now()
      WHERE public.message_requests.status = 'declined';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_direct_message_handle_request ON public.direct_messages;
CREATE TRIGGER trg_direct_message_handle_request
  AFTER INSERT ON public.direct_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_direct_message_handle_request();

-- 7. Upgrade conversation summary trigger (handles INSERT + edit/delete UPDATE)
CREATE OR REPLACE FUNCTION public.trg_direct_message_update_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_preview text;
  v_type text;
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.deleted_at IS NOT NULL THEN
    v_preview := 'Message deleted';
    v_type := 'deleted';
  ELSE
    v_type := COALESCE(NULLIF(NEW.attachment_type, ''), NULLIF(NEW.message_type, ''), 'text');
    v_preview := COALESCE(
      NULLIF(btrim(NEW.message_text), ''),
      CASE v_type
        WHEN 'audio' THEN 'Voice message'
        WHEN 'image' THEN 'Photo'
        WHEN 'video' THEN 'Video'
        WHEN 'file' THEN COALESCE(NULLIF(btrim(NEW.file_name), ''), 'File')
        ELSE v_type
      END
    );
  END IF;

  UPDATE public.conversations
  SET last_message_text = left(v_preview, 180),
      last_message_type = v_type,
      last_message_at = GREATEST(COALESCE(last_message_at, NEW.created_at), NEW.created_at),
      last_sender_id = NEW.sender_id,
      updated_at = now()
  WHERE id = NEW.conversation_id
    AND (
      TG_OP = 'INSERT'
      OR last_message_at IS NULL
      OR last_message_at <= NEW.created_at
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_direct_message_update_conversation ON public.direct_messages;
CREATE TRIGGER trg_direct_message_update_conversation
  AFTER INSERT OR UPDATE OF message_text, edited_at, deleted_at ON public.direct_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_direct_message_update_conversation();

-- 8. Upgrade mark_messages_delivered & create_direct_message_notification (supports Groups + Mutes)
CREATE OR REPLACE FUNCTION public.mark_messages_delivered()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_now timestamptz := now();
BEGIN
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  WITH target AS (
    SELECT dm.id
    FROM public.direct_messages dm
    WHERE dm.sender_id <> v_me
      AND dm.deleted_at IS NULL
      AND (
        dm.receiver_id = v_me
        OR (dm.conversation_id IS NOT NULL AND public.is_conversation_member(dm.conversation_id, v_me))
      )
      AND (
        dm.is_delivered = false
        OR NOT EXISTS (
          SELECT 1 FROM public.message_deliveries md
          WHERE md.message_id = dm.id AND md.user_id = v_me
        )
      )
  ),
  ins AS (
    INSERT INTO public.message_deliveries (message_id, user_id, delivered_at)
    SELECT id, v_me, v_now FROM target
    ON CONFLICT (message_id, user_id) DO NOTHING
  )
  UPDATE public.direct_messages dm
  SET is_delivered = true,
      delivered_at = COALESCE(dm.delivered_at, v_now)
  FROM target t
  WHERE dm.id = t.id AND dm.is_delivered = false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_messages_delivered() TO authenticated;

CREATE OR REPLACE FUNCTION public.create_direct_message_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_preview text;
  v_group_title text;
  v_member record;
BEGIN
  v_preview := left(
    coalesce(
      nullif(btrim(NEW.message_text), ''),
      CASE COALESCE(NEW.attachment_type, NEW.message_type)
        WHEN 'audio' THEN 'Sent a voice message'
        WHEN 'image' THEN 'Sent a photo'
        WHEN 'video' THEN 'Sent a video'
        WHEN 'file' THEN COALESCE('Sent a file: ' || NULLIF(btrim(NEW.file_name), ''), 'Sent a file')
        ELSE CASE WHEN NEW.attachment_url IS NOT NULL THEN 'Sent an attachment' ELSE 'Sent you a message' END
      END
    ),
    120
  );

  -- 1:1 Direct Message notification
  IF NEW.receiver_id IS NOT NULL AND NEW.receiver_id <> NEW.sender_id THEN
    IF public.is_blocked_between(NEW.sender_id, NEW.receiver_id) THEN
      RETURN NEW;
    END IF;

    IF NEW.conversation_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.conversation_mutes cm
      WHERE cm.conversation_id = NEW.conversation_id
        AND cm.user_id = NEW.receiver_id
        AND (cm.muted_until IS NULL OR cm.muted_until > now())
    ) THEN
      RETURN NEW;
    END IF;

    INSERT INTO public.user_notifications (
      user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
    ) VALUES (
      NEW.receiver_id,
      NEW.sender_id,
      'New Message',
      v_preview,
      'direct_message',
      '/chat/' || NEW.sender_id::text,
      false,
      'zev',
      now()
    );
    RETURN NEW;
  END IF;

  -- Group Message notifications for each unmuted/unblocked member
  IF NEW.receiver_id IS NULL AND NEW.conversation_id IS NOT NULL THEN
    SELECT COALESCE(NULLIF(btrim(title), ''), 'Group Chat')
    INTO v_group_title
    FROM public.conversations
    WHERE id = NEW.conversation_id;

    FOR v_member IN
      SELECT cm.user_id
      FROM public.conversation_members cm
      WHERE cm.conversation_id = NEW.conversation_id
        AND cm.user_id <> NEW.sender_id
        AND NOT public.is_blocked_between(NEW.sender_id, cm.user_id)
        AND NOT EXISTS (
          SELECT 1 FROM public.conversation_mutes m
          WHERE m.conversation_id = NEW.conversation_id
            AND m.user_id = cm.user_id
            AND (m.muted_until IS NULL OR m.muted_until > now())
        )
    LOOP
      INSERT INTO public.user_notifications (
        user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
      ) VALUES (
        v_member.user_id,
        NEW.sender_id,
        v_group_title,
        v_preview,
        'group_message',
        '/chat/conv:' || NEW.conversation_id::text,
        false,
        'zev',
        now()
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- 9. Backfill conversations summary fields from latest existing direct_messages
WITH latest_dm AS (
  SELECT DISTINCT ON (dm.conversation_id)
    dm.conversation_id,
    COALESCE(
      NULLIF(btrim(dm.message_text), ''),
      CASE COALESCE(dm.attachment_type, dm.message_type)
        WHEN 'audio' THEN 'Voice message'
        WHEN 'image' THEN 'Photo'
        WHEN 'video' THEN 'Video'
        WHEN 'file' THEN COALESCE(NULLIF(btrim(dm.file_name), ''), 'File')
        ELSE 'Message'
      END
    ) AS msg_preview,
    COALESCE(NULLIF(dm.attachment_type, ''), NULLIF(dm.message_type, ''), 'text') AS msg_type,
    dm.created_at,
    dm.sender_id
  FROM public.direct_messages dm
  WHERE dm.conversation_id IS NOT NULL
    AND dm.deleted_at IS NULL
  ORDER BY dm.conversation_id, dm.created_at DESC
)
UPDATE public.conversations c
SET last_message_text = left(l.msg_preview, 180),
    last_message_type = l.msg_type,
    last_message_at = l.created_at,
    last_sender_id = l.sender_id,
    updated_at = now()
FROM latest_dm l
WHERE c.id = l.conversation_id
  AND (c.last_message_text IS NULL OR c.last_sender_id IS NULL);

-- 10. Enable Supabase Realtime publication on all Phase 4 chat & notes tables
DO $$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'conversations',
    'conversation_members',
    'message_reactions',
    'message_reads',
    'message_deliveries',
    'message_requests',
    'user_notes'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = v_table
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
    END IF;
  END LOOP;
END $$;

