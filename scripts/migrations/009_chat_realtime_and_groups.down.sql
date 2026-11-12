-- Rollback Migration 009: Phase 4 Real-Time Chat, Notes, Groups & Requests

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
    IF EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = v_table
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I', v_table);
    END IF;
  END LOOP;
END $$;

DROP TRIGGER IF EXISTS trg_direct_message_handle_request ON public.direct_messages;
DROP FUNCTION IF EXISTS public.trg_direct_message_handle_request();
DROP FUNCTION IF EXISTS public.respond_message_request(uuid, text);
DROP FUNCTION IF EXISTS public.delete_conversation_for_me(uuid);
DROP FUNCTION IF EXISTS public.delete_message_for_everyone(uuid);
DROP FUNCTION IF EXISTS public.delete_message_for_me(uuid);
DROP FUNCTION IF EXISTS public.edit_direct_message(uuid, text);
DROP FUNCTION IF EXISTS public.create_group_conversation(text, uuid[], text);
DROP FUNCTION IF EXISTS public.get_profiles_presence(uuid[]);

DROP INDEX IF EXISTS public.idx_message_requests_recipient_pending;
DROP INDEX IF EXISTS public.idx_conversation_mutes_user;
DROP INDEX IF EXISTS public.idx_conversation_pins_user;
DROP INDEX IF EXISTS public.idx_direct_messages_unread_conv;
DROP INDEX IF EXISTS public.idx_direct_messages_conv_created;

DROP TABLE IF EXISTS public.user_notes;

