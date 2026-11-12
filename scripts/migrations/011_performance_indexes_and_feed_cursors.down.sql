-- Migration 011 DOWN: Revert Performance Indexes & Batched Keyset Cursor Feed/Reels RPCs

BEGIN;

DROP FUNCTION IF EXISTS public.get_reels_page(timestamptz, uuid, integer, boolean);
DROP FUNCTION IF EXISTS public.get_feed_posts_page(timestamptz, uuid, integer, boolean);

DROP INDEX IF EXISTS public.idx_discussion_bookmarks_user_post;
DROP INDEX IF EXISTS public.idx_post_reposts_user_post;
DROP INDEX IF EXISTS public.idx_discussion_likes_student_post;
DROP INDEX IF EXISTS public.idx_reel_bookmarks_user_reel;
DROP INDEX IF EXISTS public.idx_reel_likes_user_reel;
DROP INDEX IF EXISTS public.idx_user_mutes_pair;
DROP INDEX IF EXISTS public.idx_user_blocks_pair;
DROP INDEX IF EXISTS public.idx_user_follows_pair;
DROP INDEX IF EXISTS public.idx_hidden_posts_user_target;
DROP INDEX IF EXISTS public.idx_discussion_comments_active_post;
DROP INDEX IF EXISTS public.idx_user_stories_active_created;

COMMIT;
