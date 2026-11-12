-- 005_atomic_counters_reconcile.up.sql
-- Install atomic counter maintenance triggers across posts, reels, profiles,
-- comments, stories, and hashtags, plus helper RPCs (accept_follow_request,
-- mark_conversation_read, record_reel_view, reconcile_all_counters).

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. ATOMIC COUNTER TRIGGER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- Post Likes
CREATE OR REPLACE FUNCTION public.trg_cnt_discussion_likes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.discussion_posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.discussion_posts SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_discussion_likes ON public.discussion_likes;
CREATE TRIGGER trg_cnt_discussion_likes
  AFTER INSERT OR DELETE ON public.discussion_likes
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_discussion_likes();

-- Post Comments (respects soft delete)
CREATE OR REPLACE FUNCTION public.trg_cnt_discussion_comments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.deleted_at IS NULL THEN
    UPDATE public.discussion_posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' AND OLD.deleted_at IS NULL THEN
    UPDATE public.discussion_posts SET comments_count = GREATEST(0, comments_count - 1) WHERE id = OLD.post_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    UPDATE public.discussion_posts SET comments_count = GREATEST(0, comments_count - 1) WHERE id = NEW.post_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    UPDATE public.discussion_posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_discussion_comments ON public.discussion_comments;
CREATE TRIGGER trg_cnt_discussion_comments
  AFTER INSERT OR DELETE OR UPDATE OF deleted_at ON public.discussion_comments
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_discussion_comments();

-- Post Reposts
CREATE OR REPLACE FUNCTION public.trg_cnt_post_reposts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.discussion_posts SET reposts_count = reposts_count + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.discussion_posts SET reposts_count = GREATEST(0, reposts_count - 1) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_post_reposts ON public.post_reposts;
CREATE TRIGGER trg_cnt_post_reposts
  AFTER INSERT OR DELETE ON public.post_reposts
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_post_reposts();

-- Post Bookmarks
CREATE OR REPLACE FUNCTION public.trg_cnt_discussion_bookmarks()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.discussion_posts SET bookmarks_count = bookmarks_count + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.discussion_posts SET bookmarks_count = GREATEST(0, bookmarks_count - 1) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_discussion_bookmarks ON public.discussion_bookmarks;
CREATE TRIGGER trg_cnt_discussion_bookmarks
  AFTER INSERT OR DELETE ON public.discussion_bookmarks
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_discussion_bookmarks();

-- Reel Likes
CREATE OR REPLACE FUNCTION public.trg_cnt_reel_likes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.reels SET likes_count = likes_count + 1 WHERE id = NEW.reel_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.reels SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.reel_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_reel_likes ON public.reel_likes;
CREATE TRIGGER trg_cnt_reel_likes
  AFTER INSERT OR DELETE ON public.reel_likes
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_reel_likes();

-- Reel Comments (respects soft delete)
CREATE OR REPLACE FUNCTION public.trg_cnt_reel_comments()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.deleted_at IS NULL THEN
    UPDATE public.reels SET comments_count = comments_count + 1 WHERE id = NEW.reel_id;
  ELSIF TG_OP = 'DELETE' AND OLD.deleted_at IS NULL THEN
    UPDATE public.reels SET comments_count = GREATEST(0, comments_count - 1) WHERE id = OLD.reel_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    UPDATE public.reels SET comments_count = GREATEST(0, comments_count - 1) WHERE id = NEW.reel_id;
  ELSIF TG_OP = 'UPDATE' AND OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
    UPDATE public.reels SET comments_count = comments_count + 1 WHERE id = NEW.reel_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_reel_comments ON public.reel_comments;
CREATE TRIGGER trg_cnt_reel_comments
  AFTER INSERT OR DELETE OR UPDATE OF deleted_at ON public.reel_comments
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_reel_comments();

-- Reel Bookmarks
CREATE OR REPLACE FUNCTION public.trg_cnt_reel_bookmarks()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.reels SET bookmarks_count = bookmarks_count + 1 WHERE id = NEW.reel_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.reels SET bookmarks_count = GREATEST(0, bookmarks_count - 1) WHERE id = OLD.reel_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_reel_bookmarks ON public.reel_bookmarks;
CREATE TRIGGER trg_cnt_reel_bookmarks
  AFTER INSERT OR DELETE ON public.reel_bookmarks
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_reel_bookmarks();

-- Reel Views
CREATE OR REPLACE FUNCTION public.trg_cnt_reel_views()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.reels SET views_count = views_count + 1 WHERE id = NEW.reel_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_reel_views ON public.reel_views;
CREATE TRIGGER trg_cnt_reel_views
  AFTER INSERT ON public.reel_views
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_reel_views();

-- User Follows -> profiles.followers_count & profiles.following_count
CREATE OR REPLACE FUNCTION public.trg_cnt_user_follows()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    UPDATE public.profiles SET followers_count = followers_count + 1 WHERE id = NEW.following_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.profiles SET following_count = GREATEST(0, following_count - 1) WHERE id = OLD.follower_id;
    UPDATE public.profiles SET followers_count = GREATEST(0, followers_count - 1) WHERE id = OLD.following_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_user_follows ON public.user_follows;
CREATE TRIGGER trg_cnt_user_follows
  AFTER INSERT OR DELETE ON public.user_follows
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_user_follows();

-- Posts -> profiles.posts_count
CREATE OR REPLACE FUNCTION public.trg_cnt_profile_posts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_active boolean := false;
  v_new_active boolean := false;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_old_active := (OLD.deleted_at IS NULL AND COALESCE(OLD.is_draft, false) = false);
  END IF;
  IF TG_OP IN ('UPDATE', 'INSERT') THEN
    v_new_active := (NEW.deleted_at IS NULL AND COALESCE(NEW.is_draft, false) = false);
  END IF;

  IF NOT v_old_active AND v_new_active THEN
    UPDATE public.profiles SET posts_count = posts_count + 1 WHERE id = NEW.student_id;
  ELSIF v_old_active AND NOT v_new_active THEN
    UPDATE public.profiles SET posts_count = GREATEST(0, posts_count - 1) WHERE id = OLD.student_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_profile_posts ON public.discussion_posts;
CREATE TRIGGER trg_cnt_profile_posts
  AFTER INSERT OR DELETE OR UPDATE OF deleted_at, is_draft ON public.discussion_posts
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_profile_posts();

-- Reels -> profiles.reels_count
CREATE OR REPLACE FUNCTION public.trg_cnt_profile_reels()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_active boolean := false;
  v_new_active boolean := false;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_old_active := (OLD.deleted_at IS NULL AND COALESCE(OLD.is_published, true) = true);
  END IF;
  IF TG_OP IN ('UPDATE', 'INSERT') THEN
    v_new_active := (NEW.deleted_at IS NULL AND COALESCE(NEW.is_published, true) = true);
  END IF;

  IF NOT v_old_active AND v_new_active THEN
    UPDATE public.profiles SET reels_count = reels_count + 1 WHERE id = NEW.user_id;
  ELSIF v_old_active AND NOT v_new_active THEN
    UPDATE public.profiles SET reels_count = GREATEST(0, reels_count - 1) WHERE id = OLD.user_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_profile_reels ON public.reels;
CREATE TRIGGER trg_cnt_profile_reels
  AFTER INSERT OR DELETE OR UPDATE OF deleted_at, is_published ON public.reels
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_profile_reels();

-- Comment Likes
CREATE OR REPLACE FUNCTION public.trg_cnt_comment_likes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.comment_type = 'post' THEN
      UPDATE public.discussion_comments SET likes_count = likes_count + 1 WHERE id = NEW.comment_id;
    ELSIF NEW.comment_type = 'reel' THEN
      UPDATE public.reel_comments SET likes_count = likes_count + 1 WHERE id = NEW.comment_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.comment_type = 'post' THEN
      UPDATE public.discussion_comments SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.comment_id;
    ELSIF OLD.comment_type = 'reel' THEN
      UPDATE public.reel_comments SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.comment_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_comment_likes ON public.comment_likes;
CREATE TRIGGER trg_cnt_comment_likes
  AFTER INSERT OR DELETE ON public.comment_likes
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_comment_likes();

-- Story Views, Likes & Replies
CREATE OR REPLACE FUNCTION public.trg_cnt_story_views()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.user_stories SET views_count = views_count + 1 WHERE id = NEW.story_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.user_stories SET views_count = GREATEST(0, views_count - 1) WHERE id = OLD.story_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_story_views ON public.story_views;
CREATE TRIGGER trg_cnt_story_views
  AFTER INSERT OR DELETE ON public.story_views
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_story_views();

CREATE OR REPLACE FUNCTION public.trg_cnt_story_likes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.user_stories SET likes_count = likes_count + 1 WHERE id = NEW.story_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.user_stories SET likes_count = GREATEST(0, likes_count - 1) WHERE id = OLD.story_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_story_likes ON public.story_likes;
CREATE TRIGGER trg_cnt_story_likes
  AFTER INSERT OR DELETE ON public.story_likes
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_story_likes();

CREATE OR REPLACE FUNCTION public.trg_cnt_story_replies()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.user_stories SET replies_count = replies_count + 1 WHERE id = NEW.story_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.user_stories SET replies_count = GREATEST(0, replies_count - 1) WHERE id = OLD.story_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_story_replies ON public.story_replies;
CREATE TRIGGER trg_cnt_story_replies
  AFTER INSERT OR DELETE ON public.story_replies
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_story_replies();

-- Hashtags
CREATE OR REPLACE FUNCTION public.trg_cnt_post_hashtags()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.hashtag_id IS NOT NULL THEN
    UPDATE public.hashtags SET posts_count = COALESCE(posts_count, 0) + 1, updated_at = now() WHERE id = NEW.hashtag_id;
  ELSIF TG_OP = 'DELETE' AND OLD.hashtag_id IS NOT NULL THEN
    UPDATE public.hashtags SET posts_count = GREATEST(0, COALESCE(posts_count, 0) - 1), updated_at = now() WHERE id = OLD.hashtag_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_post_hashtags ON public.post_hashtags;
CREATE TRIGGER trg_cnt_post_hashtags
  AFTER INSERT OR DELETE ON public.post_hashtags
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_post_hashtags();

CREATE OR REPLACE FUNCTION public.trg_cnt_reel_hashtags()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.hashtag_id IS NOT NULL THEN
    UPDATE public.hashtags SET reels_count = COALESCE(reels_count, 0) + 1, updated_at = now() WHERE id = NEW.hashtag_id;
  ELSIF TG_OP = 'DELETE' AND OLD.hashtag_id IS NOT NULL THEN
    UPDATE public.hashtags SET reels_count = GREATEST(0, COALESCE(reels_count, 0) - 1), updated_at = now() WHERE id = OLD.hashtag_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cnt_reel_hashtags ON public.reel_hashtags;
CREATE TRIGGER trg_cnt_reel_hashtags
  AFTER INSERT OR DELETE ON public.reel_hashtags
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_reel_hashtags();

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. TRANSACTIONAL SECURITY DEFINER RPCS
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.accept_follow_request(p_request_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req record;
BEGIN
  SELECT * INTO v_req
  FROM public.follow_requests
  WHERE id = p_request_id AND target_id = auth.uid()
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  UPDATE public.follow_requests
  SET status = 'accepted', updated_at = now()
  WHERE id = p_request_id;

  INSERT INTO public.user_follows (follower_id, following_id)
  VALUES (v_req.requester_id, v_req.target_id)
  ON CONFLICT (follower_id, following_id) DO NOTHING;

  INSERT INTO public.user_notifications (
    user_id, sender_id, title, message, notification_type, link_url, is_read, app_source
  ) VALUES (
    v_req.requester_id,
    v_req.target_id,
    'Follow Request Accepted',
    'accepted your follow request.',
    'follow_accepted',
    v_req.target_id::text,
    false,
    'zev'
  );

  RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.accept_follow_request(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_conversation_read(p_conversation_id uuid)
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

  WITH upd AS (
    UPDATE public.direct_messages
    SET is_read = true,
        read_at = COALESCE(read_at, now()),
        is_delivered = true,
        delivered_at = COALESCE(delivered_at, now())
    WHERE conversation_id = p_conversation_id
      AND sender_id <> v_me
      AND is_read = false
    RETURNING id
  ),
  ins_reads AS (
    INSERT INTO public.message_reads (message_id, user_id)
    SELECT id, v_me FROM upd
    ON CONFLICT (message_id, user_id) DO NOTHING
  )
  SELECT count(*) INTO v_cnt FROM upd;

  UPDATE public.conversation_members
  SET last_read_at = now()
  WHERE conversation_id = p_conversation_id AND user_id = v_me;

  RETURN v_cnt;
END;
$$;
GRANT EXECUTE ON FUNCTION public.mark_conversation_read(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_reel_view(p_reel_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL OR p_reel_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.reel_views (reel_id, viewer_id)
  VALUES (p_reel_id, v_me)
  ON CONFLICT (reel_id, viewer_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_reel_view(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. DETERMINISTIC COUNTER RECONCILIATION RPC
-- ═══════════════════════════════════════════════════════════════════════════
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
      (SELECT count(*) FROM public.referrals rf WHERE rf.referrer_id = p.id AND rf.status = 'completed')::int AS refs_c
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

-- Run initial counter backfill immediately on migration up
SELECT public.reconcile_all_counters();

