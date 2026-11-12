-- 007_social_helpers_and_pins.down.sql

DROP FUNCTION IF EXISTS public.get_user_interaction_policy(uuid);
DROP FUNCTION IF EXISTS public.toggle_follow_user(uuid);
DROP FUNCTION IF EXISTS public.unblock_user_atomic(uuid);
DROP FUNCTION IF EXISTS public.block_user_atomic(uuid);

DROP TRIGGER IF EXISTS trg_notify_reel_comment_reply ON public.reel_comments;
DROP FUNCTION IF EXISTS public.trg_notify_reel_comment_reply();

DROP TRIGGER IF EXISTS trg_notify_discussion_comment_reply ON public.discussion_comments;
DROP FUNCTION IF EXISTS public.trg_notify_discussion_comment_reply();

DROP TRIGGER IF EXISTS trg_notify_follow_request ON public.follow_requests;
DROP FUNCTION IF EXISTS public.trg_notify_follow_request();

DROP TRIGGER IF EXISTS trg_sync_comment_pins ON public.comment_pins;
DROP FUNCTION IF EXISTS public.trg_sync_comment_pins();

DROP POLICY IF EXISTS user_stories_update_own ON public.user_stories;
DROP POLICY IF EXISTS user_stories_select_visible ON public.user_stories;
CREATE POLICY user_stories_select_visible ON public.user_stories
  FOR SELECT TO authenticated, anon
  USING (
    deleted_at IS NULL
    AND (expires_at > now() OR auth.uid() = user_id)
    AND (
      auth.uid() = user_id
      OR (
        COALESCE(visibility, 'public') <> 'close_friends'
        AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = user_id AND p.is_private = true)
      )
      OR (
        COALESCE(visibility, 'public') <> 'close_friends'
        AND EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = user_id)
      )
      OR (
        visibility = 'close_friends'
        AND EXISTS (SELECT 1 FROM public.close_friends cf WHERE cf.user_id = user_stories.user_id AND cf.friend_id = auth.uid())
      )
    )
  );

