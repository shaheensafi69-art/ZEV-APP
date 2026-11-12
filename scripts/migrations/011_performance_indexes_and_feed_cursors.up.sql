-- Migration 011 UP: Performance Composite Indexes & Batched Keyset Cursor Feed/Reels RPCs

BEGIN;

CREATE INDEX IF NOT EXISTS idx_user_stories_active_created
  ON public.user_stories (created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_discussion_comments_active_post
  ON public.discussion_comments (post_id, created_at ASC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_hidden_posts_user_target
  ON public.hidden_posts (user_id, target_type, target_id);

CREATE INDEX IF NOT EXISTS idx_user_follows_pair
  ON public.user_follows (follower_id, following_id);

CREATE INDEX IF NOT EXISTS idx_user_blocks_pair
  ON public.user_blocks (blocker_id, blocked_id);

CREATE INDEX IF NOT EXISTS idx_user_mutes_pair
  ON public.user_mutes (muter_id, muted_id);

CREATE INDEX IF NOT EXISTS idx_reel_likes_user_reel
  ON public.reel_likes (user_id, reel_id);

CREATE INDEX IF NOT EXISTS idx_reel_bookmarks_user_reel
  ON public.reel_bookmarks (user_id, reel_id);

CREATE INDEX IF NOT EXISTS idx_discussion_likes_student_post
  ON public.discussion_likes (student_id, post_id);

CREATE INDEX IF NOT EXISTS idx_post_reposts_user_post
  ON public.post_reposts (user_id, post_id);

CREATE INDEX IF NOT EXISTS idx_discussion_bookmarks_user_post
  ON public.discussion_bookmarks (user_id, post_id);

CREATE OR REPLACE FUNCTION public.get_feed_posts_page(
  p_cursor_created_at timestamptz DEFAULT NULL,
  p_cursor_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_following_only boolean DEFAULT false
)
RETURNS TABLE (
  id uuid,
  student_id uuid,
  title text,
  content text,
  image_url text,
  post_type text,
  visibility text,
  location text,
  edited_at timestamptz,
  created_at timestamptz,
  likes_count integer,
  comments_count integer,
  reposts_count integer,
  bookmarks_count integer,
  views_count integer,
  author_username text,
  author_first_name text,
  author_last_name text,
  author_avatar_url text,
  author_is_verified boolean,
  is_liked_by_me boolean,
  is_reposted_by_me boolean,
  is_bookmarked_by_me boolean,
  is_author_followed boolean,
  media_items jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 60);
BEGIN
  RETURN QUERY
  SELECT
    dp.id,
    dp.student_id,
    coalesce(dp.title, '') AS title,
    coalesce(dp.content, '') AS content,
    coalesce(dp.image_url, '') AS image_url,
    coalesce(dp.post_type, 'text') AS post_type,
    coalesce(dp.visibility, 'public') AS visibility,
    coalesce(dp.location, '') AS location,
    dp.edited_at,
    dp.created_at,
    coalesce(dp.likes_count, 0) AS likes_count,
    coalesce(dp.comments_count, 0) AS comments_count,
    coalesce(dp.reposts_count, 0) AS reposts_count,
    coalesce(dp.bookmarks_count, 0) AS bookmarks_count,
    coalesce(dp.views_count, 0) AS views_count,
    coalesce(pr.username, 'user') AS author_username,
    coalesce(pr.first_name, '') AS author_first_name,
    coalesce(pr.last_name, '') AS author_last_name,
    coalesce(pr.avatar_url, '') AS author_avatar_url,
    coalesce(pr.is_verified, false) AS author_is_verified,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.discussion_likes dl
      WHERE dl.post_id = dp.id AND dl.student_id = v_me
    ) END AS is_liked_by_me,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.post_reposts rep
      WHERE rep.post_id = dp.id AND rep.user_id = v_me
    ) END AS is_reposted_by_me,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.discussion_bookmarks dbm
      WHERE dbm.post_id = dp.id AND dbm.user_id = v_me
    ) END AS is_bookmarked_by_me,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.user_follows uf
      WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
    ) END AS is_author_followed,
    coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', pm.id,
            'media_type', pm.media_type,
            'media_url', pm.media_url,
            'thumbnail_url', pm.thumbnail_url,
            'width', pm.width,
            'height', pm.height,
            'duration_seconds', pm.duration_seconds,
            'sort_order', pm.sort_order
          )
          ORDER BY pm.sort_order ASC, pm.created_at ASC
        )
        FROM public.post_media pm
        WHERE pm.post_id = dp.id
      ),
      '[]'::jsonb
    ) AS media_items
  FROM public.discussion_posts dp
  JOIN public.profiles pr ON pr.id = dp.student_id
  WHERE dp.deleted_at IS NULL
    AND coalesce(dp.is_draft, false) = false
    AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
    AND coalesce(pr.is_banned, false) = false
    AND coalesce(pr.account_status, 'active') = 'active'
    AND (
      v_me = dp.student_id
      OR (
        coalesce(dp.visibility, 'public') <> 'private'
        AND (
          (
            coalesce(pr.is_private, false) = false
            AND coalesce(dp.visibility, 'public') <> 'followers'
          )
          OR (
            v_me IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM public.user_follows uf
              WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
            )
          )
        )
      )
    )
    AND (
      v_me IS NULL
      OR (
        NOT public.is_blocked_between(v_me, dp.student_id)
        AND NOT EXISTS (
          SELECT 1 FROM public.user_mutes um
          WHERE um.muter_id = v_me
            AND um.muted_id = dp.student_id
            AND coalesce(um.mute_posts, true) = true
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.hidden_posts hp
          WHERE hp.user_id = v_me
            AND hp.target_type = 'post'
            AND hp.target_id = dp.id
        )
      )
    )
    AND (
      NOT coalesce(p_following_only, false)
      OR (
        v_me IS NOT NULL
        AND (
          dp.student_id = v_me
          OR EXISTS (
            SELECT 1 FROM public.user_follows uf
            WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
          )
        )
      )
    )
    AND (
      p_cursor_created_at IS NULL
      OR (
        CASE WHEN p_cursor_id IS NOT NULL
          THEN (dp.created_at, dp.id) < (p_cursor_created_at, p_cursor_id)
          ELSE dp.created_at < p_cursor_created_at
        END
      )
    )
  ORDER BY dp.created_at DESC, dp.id DESC
  LIMIT v_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_reels_page(
  p_cursor_created_at timestamptz DEFAULT NULL,
  p_cursor_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_following_only boolean DEFAULT false
)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  title text,
  description text,
  video_url text,
  thumbnail_url text,
  category text,
  audio_name text,
  duration_seconds integer,
  views_count integer,
  likes_count integer,
  comments_count integer,
  created_at timestamptz,
  author_username text,
  author_first_name text,
  author_last_name text,
  author_avatar_url text,
  author_is_verified boolean,
  is_liked_by_me boolean,
  is_bookmarked_by_me boolean,
  is_author_followed boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 60);
BEGIN
  RETURN QUERY
  SELECT
    r.id,
    r.user_id,
    coalesce(r.title, '') AS title,
    coalesce(r.description, '') AS description,
    coalesce(r.video_url, '') AS video_url,
    coalesce(r.thumbnail_url, '') AS thumbnail_url,
    coalesce(r.category, 'Explore') AS category,
    coalesce(r.audio_name, '') AS audio_name,
    coalesce(r.duration_seconds, 0) AS duration_seconds,
    coalesce(r.views_count, 0) AS views_count,
    coalesce(r.likes_count, 0) AS likes_count,
    coalesce(r.comments_count, 0) AS comments_count,
    r.created_at,
    coalesce(pr.username, 'creator') AS author_username,
    coalesce(pr.first_name, '') AS author_first_name,
    coalesce(pr.last_name, '') AS author_last_name,
    coalesce(pr.avatar_url, '') AS author_avatar_url,
    coalesce(pr.is_verified, false) AS author_is_verified,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.reel_likes rl
      WHERE rl.reel_id = r.id AND rl.user_id = v_me
    ) END AS is_liked_by_me,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.reel_bookmarks rb
      WHERE rb.reel_id = r.id AND rb.user_id = v_me
    ) END AS is_bookmarked_by_me,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.user_follows uf
      WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
    ) END AS is_author_followed
  FROM public.reels r
  JOIN public.profiles pr ON pr.id = r.user_id
  WHERE r.deleted_at IS NULL
    AND coalesce(r.is_published, true) = true
    AND coalesce(pr.is_banned, false) = false
    AND coalesce(pr.account_status, 'active') = 'active'
    AND (
      v_me = r.user_id
      OR (
        coalesce(r.visibility, 'public') <> 'private'
        AND (
          (
            coalesce(pr.is_private, false) = false
            AND coalesce(r.visibility, 'public') <> 'followers'
          )
          OR (
            v_me IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM public.user_follows uf
              WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
            )
          )
        )
      )
    )
    AND (
      v_me IS NULL
      OR (
        NOT public.is_blocked_between(v_me, r.user_id)
        AND NOT EXISTS (
          SELECT 1 FROM public.user_mutes um
          WHERE um.muter_id = v_me
            AND um.muted_id = r.user_id
            AND coalesce(um.mute_posts, true) = true
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.hidden_posts hp
          WHERE hp.user_id = v_me
            AND hp.target_type = 'reel'
            AND hp.target_id = r.id
        )
      )
    )
    AND (
      NOT coalesce(p_following_only, false)
      OR (
        v_me IS NOT NULL
        AND (
          r.user_id = v_me
          OR EXISTS (
            SELECT 1 FROM public.user_follows uf
            WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
          )
        )
      )
    )
    AND (
      p_cursor_created_at IS NULL
      OR (
        CASE WHEN p_cursor_id IS NOT NULL
          THEN (r.created_at, r.id) < (p_cursor_created_at, p_cursor_id)
          ELSE r.created_at < p_cursor_created_at
        END
      )
    )
  ORDER BY r.created_at DESC, r.id DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_feed_posts_page(timestamptz, uuid, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_feed_posts_page(timestamptz, uuid, integer, boolean) TO authenticated, anon;

REVOKE ALL ON FUNCTION public.get_reels_page(timestamptz, uuid, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_reels_page(timestamptz, uuid, integer, boolean) TO authenticated, anon;

COMMIT;
