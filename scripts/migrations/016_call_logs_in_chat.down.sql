-- 016_call_logs_in_chat.down.sql
DROP TRIGGER IF EXISTS trg_call_session_log_to_chat ON public.call_sessions;
DROP FUNCTION IF EXISTS public.trg_call_session_log_to_chat();
DROP FUNCTION IF EXISTS public.format_call_duration(integer);

