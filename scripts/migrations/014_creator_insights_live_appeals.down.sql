-- Migration 014 DOWN: Revert Phase 9 Advanced Features cleanly

BEGIN;

DROP FUNCTION IF EXISTS public.leave_live_stream(uuid);
DROP FUNCTION IF EXISTS public.join_live_stream(uuid);
DROP FUNCTION IF EXISTS public.end_live_stream(uuid);
DROP FUNCTION IF EXISTS public.start_live_stream(text, text, text);
DROP FUNCTION IF EXISTS public.submit_restriction_appeal(text, text, uuid, text[]);
DROP FUNCTION IF EXISTS public.get_creator_insights(integer);
DROP FUNCTION IF EXISTS public.publish_post_now(uuid);
DROP FUNCTION IF EXISTS public.get_my_drafts_and_scheduled_posts();

-- Restore Migration 011 25-column get_feed_posts_page
DROP FUNCTION IF EXISTS public.get_feed_posts_page(timestamptz, uuid, integer, boolean);

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

REVOKE ALL ON FUNCTION public.get_feed_posts_page(timestamptz, uuid, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_feed_posts_page(timestamptz, uuid, integer, boolean) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.record_post_view(p_post_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_author uuid;
BEGIN
  IF v_me IS NULL OR p_post_id IS NULL THEN
    RETURN;
  END IF;

  SELECT dp.student_id INTO v_author
  FROM public.discussion_posts dp
  JOIN public.profiles pr ON pr.id = dp.student_id
  WHERE dp.id = p_post_id
    AND dp.deleted_at IS NULL
    AND COALESCE(dp.is_draft, false) = false
    AND COALESCE(pr.is_banned, false) = false
    AND COALESCE(pr.account_status, 'active') = 'active';

  IF v_author IS NULL OR public.is_blocked_between(v_me, v_author) THEN
    RETURN;
  END IF;

  INSERT INTO public.post_views (post_id, viewer_id)
  VALUES (p_post_id, v_me)
  ON CONFLICT (post_id, viewer_id) DO NOTHING;
END;
$$;

-- Restore prior policies on discussion_posts, post_media, and live_* tables
DROP POLICY IF EXISTS discussion_posts_select_visible ON public.discussion_posts;
CREATE POLICY discussion_posts_select_visible ON public.discussion_posts
  FOR SELECT TO anon, authenticated
  USING (
    (auth.uid() = student_id)
    OR (
      (deleted_at IS NULL)
      AND (is_draft = false)
      AND (
        (
          (COALESCE(visibility, 'public'::text) = 'public'::text)
          AND (NOT (EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = discussion_posts.student_id AND p.is_private = true)))
        )
        OR (
          (COALESCE(visibility, 'public'::text) = ANY (ARRAY['public'::text, 'followers'::text]))
          AND (EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = discussion_posts.student_id))
        )
      )
    )
  );

DROP POLICY IF EXISTS post_media_select_visible ON public.post_media;
CREATE POLICY post_media_select_all ON public.post_media
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS live_streams_select_visible ON public.live_streams;
CREATE POLICY live_streams_select_all ON public.live_streams
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS live_comments_select_visible ON public.live_comments;
CREATE POLICY live_comments_select ON public.live_comments
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS live_comments_insert_live ON public.live_comments;
CREATE POLICY live_comments_insert ON public.live_comments
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS live_reactions_select_visible ON public.live_reactions;
CREATE POLICY live_reactions_select ON public.live_reactions
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS live_reactions_insert_live ON public.live_reactions;
CREATE POLICY live_reactions_insert ON public.live_reactions
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS live_viewers_select_visible ON public.live_viewers;
CREATE POLICY live_viewers_select ON public.live_viewers
  FOR SELECT TO authenticated
  USING (true);

DO $$
DECLARE
  v_tbl text;
BEGIN
  FOREACH v_tbl IN ARRAY ARRAY['live_streams', 'live_comments', 'live_reactions', 'live_viewers', 'appeals']
  LOOP
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE public.%I', v_tbl);
    EXCEPTION WHEN undefined_object OR invalid_parameter_value THEN
      NULL;
    END;
  END LOOP;
END $$;

DROP INDEX IF EXISTS public.idx_reel_views_reel_viewed;
DROP INDEX IF EXISTS public.idx_post_views_post_viewed;
DROP INDEX IF EXISTS public.idx_live_streams_status_started;
DROP INDEX IF EXISTS public.idx_appeals_status_created;
DROP INDEX IF EXISTS public.idx_discussion_posts_drafts_sched;

COMMIT;
