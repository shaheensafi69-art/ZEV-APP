-- 020_profile_views_and_performance_indexes.down.sql
DROP INDEX IF EXISTS public.idx_profile_views_profile_viewed_at;
DROP INDEX IF EXISTS public.idx_profile_views_viewer_viewed_at;
DROP INDEX IF EXISTS public.idx_discussion_posts_created_at_id;
DROP INDEX IF EXISTS public.idx_reels_created_at_id;
DROP INDEX IF EXISTS public.idx_user_follows_follower_following;
DROP INDEX IF EXISTS public.idx_user_follows_following_follower;
DROP INDEX IF EXISTS public.idx_user_notifications_user_created;

DROP FUNCTION IF EXISTS public.get_profile_views_30d();
DROP FUNCTION IF EXISTS public.record_profile_view(UUID);

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.profile_views;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DROP TABLE IF EXISTS public.profile_views CASCADE;
