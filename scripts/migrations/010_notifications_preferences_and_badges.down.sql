-- Migration 010 DOWN: Revert Notification Preferences RPC & Badge Indexes

BEGIN;

DROP FUNCTION IF EXISTS public.get_or_init_notification_preferences();
DROP FUNCTION IF EXISTS public.get_unread_badge_counts();
DROP INDEX IF EXISTS public.idx_follow_requests_target_pending;
DROP INDEX IF EXISTS public.idx_user_notifications_unread_badge;

COMMIT;
