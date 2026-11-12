-- 007_social_helpers_and_pins.up.sql
-- Phase 3 helpers: story update/soft-delete RLS, comment pin sync trigger,
-- follow request & comment reply triggers, atomic block/follow RPCs,
-- safe interaction privacy policy RPC, and referral counter alignment.

-- 1. Fix user_stories select visibility for owner's soft-deleted / expired stories + add update policy
DROP POLICY IF EXISTS user_stories_select_visible ON public.user_stories;
CREATE POLICY user_stories_select_visible ON public.user_stories
  FOR SELECT TO authenticated, anon
  USING (
    auth.uid() = user_id
    OR (
      deleted_at IS NULL
      AND expires_at > now()
      AND (
        (
          COALESCE(visibility, 'public') <> 'close_friends'
          AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = user_stories.user_id AND p.is_private = true)
        )
        OR (
          COALESCE(visibility, 'public') <> 'close_friends'
          AND EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = user_stories.user_id)
        )
        OR (
          visibility = 'close_friends'
          AND EXISTS (SELECT 1 FROM public.close_friends cf WHERE cf.user_id = user_stories.user_id AND cf.friend_id = auth.uid())
        )
      )
    )
  );

DROP POLICY IF EXISTS user_stories_update_own ON public.user_stories;
CREATE POLICY user_stories_update_own ON public.user_stories
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 2. Sync is_pinned column atomically when owner inserts/deletes in comment_pins
CREATE OR REPLACE FUNCTION public.trg_sync_comment_pins()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.target_type = 'post' THEN
      UPDATE public.discussion_comments SET is_pinned = true WHERE id = NEW.comment_id AND post_id = NEW.target_id;
    ELSIF NEW.target_type = 'reel' THEN
      UPDATE public.reel_comments SET is_pinned = true WHERE id = NEW.comment_id AND reel_id = NEW.target_id;
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.target_type = 'post' THEN
      UPDATE public.discussion_comments SET is_pinned = false WHERE id = OLD.comment_id AND post_id = OLD.target_id;
    ELSIF OLD.target_type = 'reel' THEN
      UPDATE public.reel_comments SET is_pinned = false WHERE id = OLD.comment_id AND reel_id = OLD.target_id;
    END IF;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_comment_pins ON public.comment_pins;
CREATE TRIGGER trg_sync_comment_pins
  AFTER INSERT OR DELETE ON public.comment_pins
  FOR EACH ROW EXECUTE FUNCTION public.trg_sync_comment_pins();

-- 3. Notify target on follow_request insert
CREATE OR REPLACE FUNCTION public.trg_notify_follow_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'pending'
     AND NEW.requester_id <> NEW.target_id
     AND NOT public.is_blocked_between(NEW.requester_id, NEW.target_id) THEN
    INSERT INTO public.user_notifications (
      user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
    ) VALUES (
      NEW.target_id,
      NEW.requester_id,
      'Follow Request',
      'requested to follow you.',
      'follow_request',
      NEW.requester_id::text,
      false,
      'zev',
      now()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_follow_request ON public.follow_requests;
CREATE TRIGGER trg_notify_follow_request
  AFTER INSERT ON public.follow_requests
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_follow_request();

-- 4. Notify parent comment author on nested comment replies (post + reel)
CREATE OR REPLACE FUNCTION public.trg_notify_discussion_comment_reply()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_author uuid;
  v_post_owner uuid;
  v_snippet text;
BEGIN
  IF NEW.parent_comment_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT student_id INTO v_parent_author FROM public.discussion_comments WHERE id = NEW.parent_comment_id;
  SELECT student_id INTO v_post_owner FROM public.discussion_posts WHERE id = NEW.post_id;

  IF v_parent_author IS NOT NULL
     AND v_parent_author <> NEW.student_id
     AND v_parent_author IS DISTINCT FROM v_post_owner
     AND NOT public.is_blocked_between(NEW.student_id, v_parent_author) THEN
    v_snippet := left(coalesce(NEW.comment_text, ''), 80);
    INSERT INTO public.user_notifications (
      user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
    ) VALUES (
      v_parent_author,
      NEW.student_id,
      'New Reply',
      CASE WHEN v_snippet <> '' THEN 'replied: "' || v_snippet || '"' ELSE 'replied to your comment.' END,
      'comment_reply',
      NEW.post_id::text,
      false,
      'zev',
      now()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_discussion_comment_reply ON public.discussion_comments;
CREATE TRIGGER trg_notify_discussion_comment_reply
  AFTER INSERT ON public.discussion_comments
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_discussion_comment_reply();

CREATE OR REPLACE FUNCTION public.trg_notify_reel_comment_reply()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_parent_author uuid;
  v_reel_owner uuid;
  v_snippet text;
BEGIN
  IF NEW.parent_comment_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT user_id INTO v_parent_author FROM public.reel_comments WHERE id = NEW.parent_comment_id;
  SELECT user_id INTO v_reel_owner FROM public.reels WHERE id = NEW.reel_id;

  IF v_parent_author IS NOT NULL
     AND v_parent_author <> NEW.user_id
     AND v_parent_author IS DISTINCT FROM v_reel_owner
     AND NOT public.is_blocked_between(NEW.user_id, v_parent_author) THEN
    v_snippet := left(coalesce(NEW.comment_text, ''), 80);
    INSERT INTO public.user_notifications (
      user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
    ) VALUES (
      v_parent_author,
      NEW.user_id,
      'New Reply',
      CASE WHEN v_snippet <> '' THEN 'replied: "' || v_snippet || '"' ELSE 'replied to your comment.' END,
      'reel_comment',
      NEW.reel_id::text,
      false,
      'zev',
      now()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_reel_comment_reply ON public.reel_comments;
CREATE TRIGGER trg_notify_reel_comment_reply
  AFTER INSERT ON public.reel_comments
  FOR EACH ROW EXECUTE FUNCTION public.trg_notify_reel_comment_reply();

-- 5. Atomic Block / Unblock RPCs
CREATE OR REPLACE FUNCTION public.block_user_atomic(p_blocked_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL OR p_blocked_id IS NULL OR p_blocked_id = v_me THEN
    RETURN false;
  END IF;

  INSERT INTO public.user_blocks (blocker_id, blocked_id)
  VALUES (v_me, p_blocked_id)
  ON CONFLICT (blocker_id, blocked_id) DO NOTHING;

  DELETE FROM public.user_follows
  WHERE (follower_id = v_me AND following_id = p_blocked_id)
     OR (follower_id = p_blocked_id AND following_id = v_me);

  DELETE FROM public.follow_requests
  WHERE (requester_id = v_me AND target_id = p_blocked_id)
     OR (requester_id = p_blocked_id AND target_id = v_me);

  DELETE FROM public.close_friends
  WHERE (user_id = v_me AND friend_id = p_blocked_id)
     OR (user_id = p_blocked_id AND friend_id = v_me);

  DELETE FROM public.student_friends
  WHERE (sender_id = v_me AND receiver_id = p_blocked_id)
     OR (sender_id = p_blocked_id AND receiver_id = v_me);

  RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.block_user_atomic(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.unblock_user_atomic(p_blocked_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL OR p_blocked_id IS NULL THEN
    RETURN false;
  END IF;

  DELETE FROM public.user_blocks
  WHERE blocker_id = v_me AND blocked_id = p_blocked_id;

  RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.unblock_user_atomic(uuid) TO authenticated;

-- 6. Atomic Private-Aware Follow Toggle RPC
CREATE OR REPLACE FUNCTION public.toggle_follow_user(p_target_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_is_private boolean := false;
  v_exists_follow boolean := false;
  v_req_id uuid;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_target_id IS NULL OR p_target_id = v_me THEN
    RAISE EXCEPTION 'Invalid target user';
  END IF;
  IF public.is_blocked_between(v_me, p_target_id) THEN
    RETURN jsonb_build_object('status', 'blocked');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_follows
    WHERE follower_id = v_me AND following_id = p_target_id
  ) INTO v_exists_follow;

  IF v_exists_follow THEN
    DELETE FROM public.user_follows
    WHERE follower_id = v_me AND following_id = p_target_id;
    DELETE FROM public.follow_requests
    WHERE requester_id = v_me AND target_id = p_target_id;
    RETURN jsonb_build_object('status', 'unfollowed');
  END IF;

  SELECT id INTO v_req_id
  FROM public.follow_requests
  WHERE requester_id = v_me AND target_id = p_target_id AND status = 'pending';

  IF v_req_id IS NOT NULL THEN
    DELETE FROM public.follow_requests WHERE id = v_req_id;
    RETURN jsonb_build_object('status', 'cancelled');
  END IF;

  SELECT COALESCE(p.is_private, false)
  INTO v_is_private
  FROM public.profiles p
  WHERE p.id = p_target_id;

  IF v_is_private THEN
    INSERT INTO public.follow_requests (requester_id, target_id, status, updated_at)
    VALUES (v_me, p_target_id, 'pending', now())
    ON CONFLICT (requester_id, target_id) DO UPDATE
      SET status = 'pending', updated_at = now()
    RETURNING id INTO v_req_id;

    RETURN jsonb_build_object('status', 'requested', 'request_id', v_req_id);
  END IF;

  INSERT INTO public.user_follows (follower_id, following_id)
  VALUES (v_me, p_target_id)
  ON CONFLICT (follower_id, following_id) DO NOTHING;

  RETURN jsonb_build_object('status', 'following');
END;
$$;
GRANT EXECUTE ON FUNCTION public.toggle_follow_user(uuid) TO authenticated;

-- 7. Safe Interaction Privacy Policy RPC (respects hide_online_status / allow_*_from without exposing raw private rows)
CREATE OR REPLACE FUNCTION public.get_user_interaction_policy(p_target_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_is_private boolean := false;
  v_is_blocked boolean := false;
  v_is_following boolean := false;
  v_is_pending boolean := false;
  v_is_followed_by boolean := false;
  v_allow_msg text := 'everyone';
  v_allow_mention text := 'everyone';
  v_allow_tag text := 'everyone';
  v_allow_story_reply text := 'everyone';
  v_hide_online boolean := false;
BEGIN
  IF p_target_id IS NULL THEN
    RETURN jsonb_build_object('is_blocked', false);
  END IF;

  SELECT COALESCE(is_private, false) INTO v_is_private FROM public.profiles WHERE id = p_target_id;

  IF v_me IS NOT NULL THEN
    v_is_blocked := public.is_blocked_between(v_me, p_target_id);
    SELECT EXISTS (SELECT 1 FROM public.user_follows WHERE follower_id = v_me AND following_id = p_target_id) INTO v_is_following;
    SELECT EXISTS (SELECT 1 FROM public.follow_requests WHERE requester_id = v_me AND target_id = p_target_id AND status = 'pending') INTO v_is_pending;
    SELECT EXISTS (SELECT 1 FROM public.user_follows WHERE follower_id = p_target_id AND following_id = v_me) INTO v_is_followed_by;
  END IF;

  SELECT
    COALESCE(allow_messages_from, 'everyone'),
    COALESCE(allow_mentions_from, 'everyone'),
    COALESCE(allow_tags_from, 'everyone'),
    COALESCE(allow_story_replies_from, 'everyone'),
    COALESCE(hide_online_status, false)
  INTO v_allow_msg, v_allow_mention, v_allow_tag, v_allow_story_reply, v_hide_online
  FROM public.user_privacy_settings
  WHERE user_id = p_target_id;

  v_allow_msg := COALESCE(v_allow_msg, 'everyone');
  v_allow_mention := COALESCE(v_allow_mention, 'everyone');
  v_allow_tag := COALESCE(v_allow_tag, 'everyone');
  v_allow_story_reply := COALESCE(v_allow_story_reply, 'everyone');
  v_hide_online := COALESCE(v_hide_online, false);

  RETURN jsonb_build_object(
    'is_blocked', v_is_blocked,
    'is_private', v_is_private,
    'is_following', v_is_following,
    'is_pending_request', v_is_pending,
    'is_followed_by', v_is_followed_by,
    'hide_online_status', v_hide_online,
    'can_view_content', (NOT v_is_blocked AND (v_me = p_target_id OR NOT v_is_private OR v_is_following)),
    'can_message', (NOT v_is_blocked AND (v_allow_msg = 'everyone' OR (v_allow_msg = 'followers' AND (v_is_following OR v_is_followed_by)))),
    'can_mention', (NOT v_is_blocked AND (v_allow_mention = 'everyone' OR (v_allow_mention = 'followers' AND (v_is_following OR v_is_followed_by)))),
    'can_tag', (NOT v_is_blocked AND (v_allow_tag = 'everyone' OR (v_allow_tag = 'followers' AND (v_is_following OR v_is_followed_by)))),
    'can_reply_story', (NOT v_is_blocked AND (v_allow_story_reply = 'everyone' OR (v_allow_story_reply = 'followers' AND (v_is_following OR v_is_followed_by))))
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_user_interaction_policy(uuid) TO anon, authenticated;

-- 8. Align reconcile_all_counters referral status check with 'verified' + 'completed'
CREATE OR REPLACE FUNCTION public.reconcile_all_counters()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_posts int := 0;
  v_reels int := 0;
  v_profiles int := 0;
  v_stories int := 0;
  v_hashtags int := 0;
BEGIN
  WITH p_counts AS (
    SELECT
      dp.id,
      (SELECT count(*) FROM public.discussion_likes dl WHERE dl.post_id = dp.id)::int AS likes_c,
      (SELECT count(*) FROM public.discussion_comments dc WHERE dc.post_id = dp.id AND dc.deleted_at IS NULL)::int AS comments_c,
      (SELECT count(*) FROM public.post_reposts pr WHERE pr.post_id = dp.id)::int AS reposts_c,
      (SELECT count(*) FROM public.discussion_bookmarks db WHERE db.post_id = dp.id)::int AS bookmarks_c
    FROM public.discussion_posts dp
  ),
  upd_posts AS (
    UPDATE public.discussion_posts dp
    SET likes_count = c.likes_c,
        comments_count = c.comments_c,
        reposts_count = c.reposts_c,
        bookmarks_count = c.bookmarks_c
    FROM p_counts c
    WHERE dp.id = c.id
      AND (dp.likes_count IS DISTINCT FROM c.likes_c
        OR dp.comments_count IS DISTINCT FROM c.comments_c
        OR dp.reposts_count IS DISTINCT FROM c.reposts_c
        OR dp.bookmarks_count IS DISTINCT FROM c.bookmarks_c)
    RETURNING dp.id
  )
  SELECT count(*) INTO v_posts FROM upd_posts;

  WITH r_counts AS (
    SELECT
      r.id,
      (SELECT count(*) FROM public.reel_likes rl WHERE rl.reel_id = r.id)::int AS likes_c,
      (SELECT count(*) FROM public.reel_comments rc WHERE rc.reel_id = r.id AND rc.deleted_at IS NULL)::int AS comments_c,
      (SELECT count(*) FROM public.reel_bookmarks rb WHERE rb.reel_id = r.id)::int AS bookmarks_c,
      GREATEST(
        COALESCE(r.views_count, 0),
        (SELECT count(*) FROM public.reel_views rv WHERE rv.reel_id = r.id)::int
      ) AS views_c
    FROM public.reels r
  ),
  upd_reels AS (
    UPDATE public.reels r
    SET likes_count = c.likes_c,
        comments_count = c.comments_c,
        bookmarks_count = c.bookmarks_c,
        views_count = c.views_c
    FROM r_counts c
    WHERE r.id = c.id
      AND (r.likes_count IS DISTINCT FROM c.likes_c
        OR r.comments_count IS DISTINCT FROM c.comments_c
        OR r.bookmarks_count IS DISTINCT FROM c.bookmarks_c
        OR r.views_count IS DISTINCT FROM c.views_c)
    RETURNING r.id
  )
  SELECT count(*) INTO v_reels FROM upd_reels;

  WITH u_counts AS (
    SELECT
      p.id,
      (SELECT count(*) FROM public.user_follows uf WHERE uf.following_id = p.id)::int AS followers_c,
      (SELECT count(*) FROM public.user_follows uf WHERE uf.follower_id = p.id)::int AS following_c,
      (SELECT count(*) FROM public.discussion_posts dp WHERE dp.student_id = p.id AND dp.deleted_at IS NULL AND COALESCE(dp.is_draft, false) = false)::int AS posts_c,
      (SELECT count(*) FROM public.reels r WHERE r.user_id = p.id AND r.deleted_at IS NULL AND COALESCE(r.is_published, true) = true)::int AS reels_c,
      (SELECT count(*) FROM public.referrals rf WHERE rf.referrer_id = p.id AND COALESCE(rf.status, 'verified') IN ('completed', 'verified'))::int AS refs_c
    FROM public.profiles p
  ),
  upd_profiles AS (
    UPDATE public.profiles p
    SET followers_count = c.followers_c,
        following_count = c.following_c,
        posts_count = c.posts_c,
        reels_count = c.reels_c,
        referral_count = GREATEST(COALESCE(p.referral_count, 0), c.refs_c)
    FROM u_counts c
    WHERE p.id = c.id
      AND (p.followers_count IS DISTINCT FROM c.followers_c
        OR p.following_count IS DISTINCT FROM c.following_c
        OR p.posts_count IS DISTINCT FROM c.posts_c
        OR p.reels_count IS DISTINCT FROM c.reels_c)
    RETURNING p.id
  )
  SELECT count(*) INTO v_profiles FROM upd_profiles;

  WITH s_counts AS (
    SELECT
      us.id,
      (SELECT count(*) FROM public.story_views sv WHERE sv.story_id = us.id)::int AS views_c,
      (SELECT count(*) FROM public.story_likes sl WHERE sl.story_id = us.id)::int AS likes_c,
      (SELECT count(*) FROM public.story_replies sr WHERE sr.story_id = us.id)::int AS replies_c
    FROM public.user_stories us
  ),
  upd_stories AS (
    UPDATE public.user_stories us
    SET views_count = c.views_c,
        likes_count = c.likes_c,
        replies_count = c.replies_c
    FROM s_counts c
    WHERE us.id = c.id
      AND (us.views_count IS DISTINCT FROM c.views_c
        OR us.likes_count IS DISTINCT FROM c.likes_c
        OR us.replies_count IS DISTINCT FROM c.replies_c)
    RETURNING us.id
  )
  SELECT count(*) INTO v_stories FROM upd_stories;

  WITH h_counts AS (
    SELECT
      h.id,
      (SELECT count(*) FROM public.post_hashtags ph WHERE ph.hashtag_id = h.id)::int AS p_c,
      (SELECT count(*) FROM public.reel_hashtags rh WHERE rh.hashtag_id = h.id)::int AS r_c
    FROM public.hashtags h
  ),
  upd_hashtags AS (
    UPDATE public.hashtags h
    SET posts_count = c.p_c,
        reels_count = c.r_c
    FROM h_counts c
    WHERE h.id = c.id
      AND (h.posts_count IS DISTINCT FROM c.p_c OR h.reels_count IS DISTINCT FROM c.r_c)
    RETURNING h.id
  )
  SELECT count(*) INTO v_hashtags FROM upd_hashtags;

  RETURN jsonb_build_object(
    'reconciled_posts', v_posts,
    'reconciled_reels', v_reels,
    'reconciled_profiles', v_profiles,
    'reconciled_stories', v_stories,
    'reconciled_hashtags', v_hashtags
  );
END;
$$;

