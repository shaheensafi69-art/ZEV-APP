-- 003_rls_hardening.down.sql
DROP TRIGGER IF EXISTS trg_protect_profile_privileged_columns ON public.profiles;
DROP FUNCTION IF EXISTS public.protect_profile_privileged_columns();

DROP POLICY IF EXISTS admin_audit_logs_select_admin ON public.admin_audit_logs;
DROP POLICY IF EXISTS message_reactions_select ON public.message_reactions;
DROP POLICY IF EXISTS message_reactions_insert ON public.message_reactions;
DROP POLICY IF EXISTS message_reactions_delete ON public.message_reactions;
DROP POLICY IF EXISTS referrals_select_own ON public.referrals;
DROP POLICY IF EXISTS story_views_select ON public.story_views;
DROP POLICY IF EXISTS story_views_insert_own ON public.story_views;
DROP POLICY IF EXISTS subscriptions_select_own ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_insert_pending_own ON public.subscriptions;
DROP POLICY IF EXISTS user_restrictions_select_own ON public.user_restrictions;

DROP POLICY IF EXISTS discussion_posts_update_own ON public.discussion_posts;
DROP POLICY IF EXISTS discussion_posts_delete_own ON public.discussion_posts;
DROP POLICY IF EXISTS discussion_comments_delete_post_owner ON public.discussion_comments;
DROP POLICY IF EXISTS post_hashtags_insert_owner ON public.post_hashtags;
DROP POLICY IF EXISTS post_hashtags_delete_owner ON public.post_hashtags;
DROP POLICY IF EXISTS reel_hashtags_insert_owner ON public.reel_hashtags;
DROP POLICY IF EXISTS reel_hashtags_delete_owner ON public.reel_hashtags;
DROP POLICY IF EXISTS hashtags_insert_auth ON public.hashtags;
DROP POLICY IF EXISTS direct_messages_insert_unblocked ON public.direct_messages;
DROP POLICY IF EXISTS user_follows_insert_unblocked ON public.user_follows;
DROP POLICY IF EXISTS user_follows_delete_participant ON public.user_follows;
DROP POLICY IF EXISTS user_notifications_insert_sender ON public.user_notifications;

DROP FUNCTION IF EXISTS public.is_blocked_between(uuid, uuid);

