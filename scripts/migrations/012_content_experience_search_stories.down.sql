-- Migration 012 DOWN: Revert Phase 7 Hashtag Sync, Search, Explore/Discover, Story RPCs & Triggers

BEGIN;

DROP FUNCTION IF EXISTS public.get_close_friends_profiles(text);
DROP FUNCTION IF EXISTS public.toggle_close_friend(uuid);
DROP FUNCTION IF EXISTS public.get_story_insights_and_viewers(uuid);
DROP FUNCTION IF EXISTS public.record_story_view(uuid);
DROP FUNCTION IF EXISTS public.get_story_feed_trays();
DROP FUNCTION IF EXISTS public.get_discover_creators(text, text, integer);
DROP FUNCTION IF EXISTS public.get_explore_grid_page(text, integer, integer);
DROP FUNCTION IF EXISTS public.clear_search_history(uuid);
DROP FUNCTION IF EXISTS public.get_recent_searches(integer);
DROP FUNCTION IF EXISTS public.save_search_history(text, text, uuid);
DROP FUNCTION IF EXISTS public.search_unified_content(text, integer);
DROP FUNCTION IF EXISTS public.get_hashtag_content(text, integer);
DROP FUNCTION IF EXISTS public.get_trending_hashtags(integer);

DROP TRIGGER IF EXISTS tr_notify_story_reaction ON public.story_reactions;
DROP FUNCTION IF EXISTS public.notify_on_story_reaction();

DROP TRIGGER IF EXISTS tr_notify_story_reply ON public.story_replies;
DROP FUNCTION IF EXISTS public.notify_on_story_reply();

DROP FUNCTION IF EXISTS public.record_post_view(uuid);
DROP TRIGGER IF EXISTS trg_cnt_post_views ON public.post_views;
DROP FUNCTION IF EXISTS public.trg_cnt_post_views();

DROP TRIGGER IF EXISTS trg_sync_reel_hashtags ON public.reels;
DROP TRIGGER IF EXISTS trg_sync_post_hashtags ON public.discussion_posts;
DROP FUNCTION IF EXISTS public.trg_fn_sync_reel_hashtags();
DROP FUNCTION IF EXISTS public.trg_fn_sync_post_hashtags();
DROP FUNCTION IF EXISTS public.sync_content_hashtags(text, uuid, text, boolean);
DROP FUNCTION IF EXISTS public.extract_hashtags(text);

DROP POLICY IF EXISTS story_reactions_delete ON public.story_reactions;
DROP POLICY IF EXISTS story_reactions_update ON public.story_reactions;
ALTER TABLE public.story_reactions DROP CONSTRAINT IF EXISTS uq_story_reactions_story_user;

DROP POLICY IF EXISTS "Story Likes Select Policy" ON public.story_likes;
CREATE POLICY "Story Likes Select Policy" ON public.story_likes
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Story Likes Insert Policy" ON public.story_likes;
CREATE POLICY "Story Likes Insert Policy" ON public.story_likes
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS user_stories_select_visible ON public.user_stories;
CREATE POLICY user_stories_select_visible ON public.user_stories
  FOR SELECT TO anon, authenticated
  USING (
    auth.uid() = user_id
    OR (
      deleted_at IS NULL
      AND expires_at > now()
      AND (
        (COALESCE(visibility, 'public') <> 'close_friends' AND NOT EXISTS (
          SELECT 1 FROM public.profiles p WHERE p.id = user_stories.user_id AND p.is_private = true
        ))
        OR (COALESCE(visibility, 'public') <> 'close_friends' AND EXISTS (
          SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = user_stories.user_id
        ))
        OR (visibility = 'close_friends' AND EXISTS (
          SELECT 1 FROM public.close_friends cf WHERE cf.user_id = user_stories.user_id AND cf.friend_id = auth.uid()
        ))
      )
    )
  );

DROP INDEX IF EXISTS public.idx_reel_hashtags_hashtag;
DROP INDEX IF EXISTS public.idx_post_hashtags_hashtag;
DROP INDEX IF EXISTS public.idx_hashtags_trending;
DROP INDEX IF EXISTS public.uq_hashtags_lower_tag;

COMMIT;
