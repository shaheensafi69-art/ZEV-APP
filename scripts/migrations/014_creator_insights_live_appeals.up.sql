-- Migration 014 UP: Phase 9 Advanced Features
-- Carousels/Collaborators/Tagging/Drafts/Scheduling, Creator Insights,
-- Standing Appeals, and Interactive ZEV Live Chat & Presence Rooms.

BEGIN;

-- =============================================================================
-- 1. Performance & Query Indexes
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_discussion_posts_drafts_sched
  ON public.discussion_posts (student_id, scheduled_at, created_at DESC)
  WHERE deleted_at IS NULL AND (is_draft = true OR scheduled_at IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_appeals_status_created
  ON public.appeals (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_live_streams_status_started
  ON public.live_streams (status, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_post_views_post_viewed
  ON public.post_views (post_id, viewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_reel_views_reel_viewed
  ON public.reel_views (reel_id, viewed_at DESC);

-- =============================================================================
-- 2. Scheduled Post & Carousel Media RLS Hardening + View Guard
-- =============================================================================
DROP POLICY IF EXISTS discussion_posts_select_visible ON public.discussion_posts;
CREATE POLICY discussion_posts_select_visible ON public.discussion_posts
  FOR SELECT TO anon, authenticated
  USING (
    auth.uid() = student_id
    OR (
      deleted_at IS NULL
      AND COALESCE(is_draft, false) = false
      AND (scheduled_at IS NULL OR scheduled_at <= now())
      AND CASE
            WHEN auth.uid() IS NULL THEN true
            ELSE NOT public.is_blocked_between(auth.uid(), discussion_posts.student_id)
          END
      AND EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = discussion_posts.student_id
          AND COALESCE(p.is_banned, false) = false
          AND COALESCE(p.account_status, 'active') = 'active'
          AND (
            (
              COALESCE(discussion_posts.visibility, 'public') = 'public'
              AND COALESCE(p.is_private, false) = false
            )
            OR (
              COALESCE(discussion_posts.visibility, 'public') IN ('public', 'followers')
              AND auth.uid() IS NOT NULL
              AND EXISTS (
                SELECT 1
                FROM public.user_follows uf
                WHERE uf.follower_id = auth.uid()
                  AND uf.following_id = discussion_posts.student_id
              )
            )
          )
      )
    )
  );

DROP POLICY IF EXISTS post_media_select_all ON public.post_media;
DROP POLICY IF EXISTS post_media_select_visible ON public.post_media;
CREATE POLICY post_media_select_visible ON public.post_media
  FOR SELECT TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.discussion_posts dp
      JOIN public.profiles p ON p.id = dp.student_id
      WHERE dp.id = post_media.post_id
        AND (
          dp.student_id = auth.uid()
          OR (
            dp.deleted_at IS NULL
            AND COALESCE(dp.is_draft, false) = false
            AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
            AND COALESCE(p.is_banned, false) = false
            AND COALESCE(p.account_status, 'active') = 'active'
            AND CASE
                  WHEN auth.uid() IS NULL THEN true
                  ELSE NOT public.is_blocked_between(auth.uid(), dp.student_id)
                END
            AND (
              (
                COALESCE(dp.visibility, 'public') = 'public'
                AND COALESCE(p.is_private, false) = false
              )
              OR (
                COALESCE(dp.visibility, 'public') IN ('public', 'followers')
                AND auth.uid() IS NOT NULL
                AND EXISTS (
                  SELECT 1
                  FROM public.user_follows uf
                  WHERE uf.follower_id = auth.uid()
                    AND uf.following_id = dp.student_id
                )
              )
            )
          )
        )
    )
  );

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
    AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
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

-- =============================================================================
-- 3. Upgraded Feed RPC (+ Collaborators & Tagged Users Hydration) + Drafts/Scheduling
-- =============================================================================
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
  media_items jsonb,
  collaborator_ids uuid[],
  tagged_user_ids uuid[],
  collaborator_profiles jsonb,
  tagged_profiles jsonb
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
    ) AS media_items,
    coalesce(dp.collaborator_ids, '{}'::uuid[]) AS collaborator_ids,
    coalesce(dp.tagged_user_ids, '{}'::uuid[]) AS tagged_user_ids,
    coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', cp.id,
            'username', coalesce(cp.username, 'user'),
            'first_name', coalesce(cp.first_name, ''),
            'last_name', coalesce(cp.last_name, ''),
            'avatar_url', coalesce(cp.avatar_url, ''),
            'is_verified', coalesce(cp.is_verified, false)
          )
          ORDER BY array_position(dp.collaborator_ids, cp.id)
        )
        FROM public.profiles cp
        WHERE cp.id = ANY(coalesce(dp.collaborator_ids, '{}'::uuid[]))
          AND coalesce(cp.is_banned, false) = false
          AND coalesce(cp.account_status, 'active') = 'active'
          AND (v_me IS NULL OR NOT public.is_blocked_between(v_me, cp.id))
      ),
      '[]'::jsonb
    ) AS collaborator_profiles,
    coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', tp.id,
            'username', coalesce(tp.username, 'user'),
            'first_name', coalesce(tp.first_name, ''),
            'last_name', coalesce(tp.last_name, ''),
            'avatar_url', coalesce(tp.avatar_url, ''),
            'is_verified', coalesce(tp.is_verified, false)
          )
          ORDER BY array_position(dp.tagged_user_ids, tp.id)
        )
        FROM public.profiles tp
        WHERE tp.id = ANY(coalesce(dp.tagged_user_ids, '{}'::uuid[]))
          AND coalesce(tp.is_banned, false) = false
          AND coalesce(tp.account_status, 'active') = 'active'
          AND (v_me IS NULL OR NOT public.is_blocked_between(v_me, tp.id))
      ),
      '[]'::jsonb
    ) AS tagged_profiles
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

CREATE OR REPLACE FUNCTION public.get_my_drafts_and_scheduled_posts()
RETURNS TABLE (
  id uuid,
  student_id uuid,
  title text,
  content text,
  image_url text,
  post_type text,
  visibility text,
  location text,
  is_draft boolean,
  scheduled_at timestamptz,
  published_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  media_items jsonb,
  collaborator_ids uuid[],
  tagged_user_ids uuid[],
  collaborator_profiles jsonb,
  tagged_profiles jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN
    RETURN;
  END IF;

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
    coalesce(dp.is_draft, false) AS is_draft,
    dp.scheduled_at,
    dp.published_at,
    dp.created_at,
    dp.updated_at,
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
    ) AS media_items,
    coalesce(dp.collaborator_ids, '{}'::uuid[]) AS collaborator_ids,
    coalesce(dp.tagged_user_ids, '{}'::uuid[]) AS tagged_user_ids,
    coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', cp.id,
            'username', coalesce(cp.username, 'user'),
            'first_name', coalesce(cp.first_name, ''),
            'last_name', coalesce(cp.last_name, ''),
            'avatar_url', coalesce(cp.avatar_url, ''),
            'is_verified', coalesce(cp.is_verified, false)
          )
          ORDER BY array_position(dp.collaborator_ids, cp.id)
        )
        FROM public.profiles cp
        WHERE cp.id = ANY(coalesce(dp.collaborator_ids, '{}'::uuid[]))
      ),
      '[]'::jsonb
    ) AS collaborator_profiles,
    coalesce(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', tp.id,
            'username', coalesce(tp.username, 'user'),
            'first_name', coalesce(tp.first_name, ''),
            'last_name', coalesce(tp.last_name, ''),
            'avatar_url', coalesce(tp.avatar_url, ''),
            'is_verified', coalesce(tp.is_verified, false)
          )
          ORDER BY array_position(dp.tagged_user_ids, tp.id)
        )
        FROM public.profiles tp
        WHERE tp.id = ANY(coalesce(dp.tagged_user_ids, '{}'::uuid[]))
      ),
      '[]'::jsonb
    ) AS tagged_profiles
  FROM public.discussion_posts dp
  WHERE dp.student_id = v_me
    AND dp.deleted_at IS NULL
    AND (
      coalesce(dp.is_draft, false) = true
      OR (dp.scheduled_at IS NOT NULL AND dp.scheduled_at > now())
    )
  ORDER BY coalesce(dp.scheduled_at, dp.updated_at, dp.created_at) DESC, dp.id DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_drafts_and_scheduled_posts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_drafts_and_scheduled_posts() TO authenticated;

CREATE OR REPLACE FUNCTION public.publish_post_now(p_post_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_row jsonb;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;
  IF p_post_id IS NULL THEN
    RAISE EXCEPTION 'Post id is required.' USING ERRCODE = '22023';
  END IF;

  UPDATE public.discussion_posts
  SET is_draft = false,
      scheduled_at = NULL,
      published_at = now(),
      created_at = now(),
      updated_at = now()
  WHERE id = p_post_id
    AND student_id = v_me
    AND deleted_at IS NULL
  RETURNING to_jsonb(discussion_posts.*) INTO v_row;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'Draft or scheduled post not found or permission denied.' USING ERRCODE = 'P0001';
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_post_now(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_post_now(uuid) TO authenticated;

-- =============================================================================
-- 4. Creator Insights & Analytics RPC (Windowed + All-Time Without View Double-Counting)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_creator_insights(p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_days integer := least(greatest(coalesce(p_days, 30), 7), 90);
  v_since timestamptz := date_trunc('day', now() - make_interval(days => v_days - 1));
  v_prof public.profiles%ROWTYPE;
  v_sub jsonb;
  v_verif jsonb;
  v_ads jsonb;
  v_overview jsonb;
  v_series jsonb;
  v_top_posts jsonb;
  v_top_reels jsonb;

  v_total_posts int := 0;
  v_total_reels int := 0;
  v_drafts_count int := 0;
  v_scheduled_count int := 0;
  v_all_post_views bigint := 0;
  v_all_reel_views bigint := 0;
  v_period_post_views bigint := 0;
  v_period_reel_views bigint := 0;
  v_total_likes bigint := 0;
  v_total_comments bigint := 0;
  v_total_reposts bigint := 0;
  v_total_bookmarks bigint := 0;
  v_total_shares bigint := 0;
  v_followers_gained bigint := 0;
  v_all_views bigint := 0;
  v_period_views bigint := 0;
  v_engagements bigint := 0;
  v_engagement_rate numeric := 0;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_prof FROM public.profiles WHERE id = v_me;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found.' USING ERRCODE = 'P0001';
  END IF;

  SELECT
    count(*) FILTER (
      WHERE deleted_at IS NULL
        AND coalesce(is_draft, false) = false
        AND (scheduled_at IS NULL OR scheduled_at <= now())
    )::int,
    count(*) FILTER (
      WHERE deleted_at IS NULL
        AND coalesce(is_draft, false) = true
    )::int,
    count(*) FILTER (
      WHERE deleted_at IS NULL
        AND coalesce(is_draft, false) = false
        AND scheduled_at IS NOT NULL
        AND scheduled_at > now()
    )::int,
    coalesce(sum(GREATEST(coalesce(dp.views_count, 0), coalesce(pv_c.cnt, 0))) FILTER (
      WHERE deleted_at IS NULL
        AND coalesce(is_draft, false) = false
        AND (scheduled_at IS NULL OR scheduled_at <= now())
    ), 0)::bigint,
    coalesce(sum(coalesce(dp.likes_count, 0)) FILTER (
      WHERE deleted_at IS NULL
        AND coalesce(is_draft, false) = false
        AND (scheduled_at IS NULL OR scheduled_at <= now())
    ), 0)::bigint,
    coalesce(sum(coalesce(dp.comments_count, 0)) FILTER (
      WHERE deleted_at IS NULL
        AND coalesce(is_draft, false) = false
        AND (scheduled_at IS NULL OR scheduled_at <= now())
    ), 0)::bigint,
    coalesce(sum(coalesce(dp.reposts_count, 0)) FILTER (
      WHERE deleted_at IS NULL
        AND coalesce(is_draft, false) = false
        AND (scheduled_at IS NULL OR scheduled_at <= now())
    ), 0)::bigint,
    coalesce(sum(coalesce(dp.bookmarks_count, 0)) FILTER (
      WHERE deleted_at IS NULL
        AND coalesce(is_draft, false) = false
        AND (scheduled_at IS NULL OR scheduled_at <= now())
    ), 0)::bigint
  INTO
    v_total_posts,
    v_drafts_count,
    v_scheduled_count,
    v_all_post_views,
    v_total_likes,
    v_total_comments,
    v_total_reposts,
    v_total_bookmarks
  FROM public.discussion_posts dp
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS cnt
    FROM public.post_views pv
    WHERE pv.post_id = dp.id
  ) pv_c ON true
  WHERE dp.student_id = v_me;

  SELECT
    count(*)::int,
    coalesce(sum(GREATEST(coalesce(r.views_count, 0), coalesce(rv_c.cnt, 0))), 0)::bigint,
    v_total_likes + coalesce(sum(coalesce(r.likes_count, 0)), 0)::bigint,
    v_total_comments + coalesce(sum(coalesce(r.comments_count, 0)), 0)::bigint,
    v_total_bookmarks + coalesce(sum(coalesce(r.bookmarks_count, 0)), 0)::bigint,
    coalesce(sum(coalesce(r.shares_count, 0)), 0)::bigint
  INTO
    v_total_reels,
    v_all_reel_views,
    v_total_likes,
    v_total_comments,
    v_total_bookmarks,
    v_total_shares
  FROM public.reels r
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS cnt
    FROM public.reel_views rv
    WHERE rv.reel_id = r.id
  ) rv_c ON true
  WHERE r.user_id = v_me
    AND r.deleted_at IS NULL
    AND coalesce(r.is_published, true) = true;

  SELECT count(*)::bigint
  INTO v_period_post_views
  FROM public.post_views pv
  JOIN public.discussion_posts dp ON dp.id = pv.post_id
  WHERE dp.student_id = v_me
    AND dp.deleted_at IS NULL
    AND coalesce(dp.is_draft, false) = false
    AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
    AND pv.viewed_at >= v_since;

  SELECT count(*)::bigint
  INTO v_period_reel_views
  FROM public.reel_views rv
  JOIN public.reels r ON r.id = rv.reel_id
  WHERE r.user_id = v_me
    AND r.deleted_at IS NULL
    AND coalesce(r.is_published, true) = true
    AND rv.viewed_at >= v_since;

  SELECT count(*)::bigint
  INTO v_followers_gained
  FROM public.user_follows uf
  WHERE uf.following_id = v_me
    AND uf.created_at >= v_since;

  v_all_views := v_all_post_views + v_all_reel_views;
  v_period_views := v_period_post_views + v_period_reel_views;
  v_engagements := v_total_likes + v_total_comments + v_total_reposts + v_total_bookmarks + v_total_shares;
  v_engagement_rate := CASE
    WHEN v_all_views > 0 THEN round((v_engagements::numeric * 100.0) / v_all_views::numeric, 2)
    WHEN v_engagements > 0 THEN 100.0
    ELSE 0.0
  END;

  v_overview := jsonb_build_object(
    'followers_count', coalesce(v_prof.followers_count, 0),
    'following_count', coalesce(v_prof.following_count, 0),
    'followers_gained', v_followers_gained,
    'total_posts', v_total_posts,
    'total_reels', v_total_reels,
    'drafts_count', v_drafts_count,
    'scheduled_count', v_scheduled_count,
    'total_views', v_all_views,
    'post_views', v_all_post_views,
    'reel_views', v_all_reel_views,
    'period_views', v_period_views,
    'period_post_views', v_period_post_views,
    'period_reel_views', v_period_reel_views,
    'total_likes', v_total_likes,
    'total_comments', v_total_comments,
    'total_reposts', v_total_reposts,
    'total_bookmarks', v_total_bookmarks,
    'total_shares', v_total_shares,
    'total_engagements', v_engagements,
    'engagement_rate', v_engagement_rate
  );

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'date', to_char(d.day_dt AT TIME ZONE 'UTC', 'YYYY-MM-DD'),
        'label', to_char(d.day_dt AT TIME ZONE 'UTC', 'MM/DD'),
        'post_views', coalesce(pv_day.cnt, 0),
        'reel_views', coalesce(rv_day.cnt, 0),
        'views', coalesce(pv_day.cnt, 0) + coalesce(rv_day.cnt, 0),
        'followers_gained', coalesce(fg_day.cnt, 0)
      )
      ORDER BY d.day_dt ASC
    ),
    '[]'::jsonb
  )
  INTO v_series
  FROM generate_series(date_trunc('day', v_since), date_trunc('day', now()), interval '1 day') AS d(day_dt)
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS cnt
    FROM public.post_views pv
    JOIN public.discussion_posts dp ON dp.id = pv.post_id
    WHERE dp.student_id = v_me
      AND dp.deleted_at IS NULL
      AND pv.viewed_at >= d.day_dt
      AND pv.viewed_at < (d.day_dt + interval '1 day')
  ) pv_day ON true
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS cnt
    FROM public.reel_views rv
    JOIN public.reels r ON r.id = rv.reel_id
    WHERE r.user_id = v_me
      AND r.deleted_at IS NULL
      AND rv.viewed_at >= d.day_dt
      AND rv.viewed_at < (d.day_dt + interval '1 day')
  ) rv_day ON true
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS cnt
    FROM public.user_follows uf
    WHERE uf.following_id = v_me
      AND uf.created_at >= d.day_dt
      AND uf.created_at < (d.day_dt + interval '1 day')
  ) fg_day ON true;

  SELECT coalesce(
    jsonb_agg(t.obj),
    '[]'::jsonb
  )
  INTO v_top_posts
  FROM (
    SELECT jsonb_build_object(
      'id', dp.id,
      'title', coalesce(dp.title, ''),
      'content', coalesce(dp.content, ''),
      'image_url', coalesce(NULLIF(dp.image_url, ''), (
        SELECT pm.media_url FROM public.post_media pm
        WHERE pm.post_id = dp.id
        ORDER BY pm.sort_order ASC, pm.created_at ASC
        LIMIT 1
      ), ''),
      'created_at', dp.created_at,
      'views_count', GREATEST(coalesce(dp.views_count, 0), coalesce(pv_c.cnt, 0)),
      'likes_count', coalesce(dp.likes_count, 0),
      'comments_count', coalesce(dp.comments_count, 0),
      'reposts_count', coalesce(dp.reposts_count, 0),
      'bookmarks_count', coalesce(dp.bookmarks_count, 0)
    ) AS obj
    FROM public.discussion_posts dp
    LEFT JOIN LATERAL (
      SELECT count(*)::int AS cnt FROM public.post_views pv WHERE pv.post_id = dp.id
    ) pv_c ON true
    WHERE dp.student_id = v_me
      AND dp.deleted_at IS NULL
      AND coalesce(dp.is_draft, false) = false
      AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
    ORDER BY
      (
        GREATEST(coalesce(dp.views_count, 0), coalesce(pv_c.cnt, 0))
        + coalesce(dp.likes_count, 0) * 3
        + coalesce(dp.comments_count, 0) * 4
        + coalesce(dp.reposts_count, 0) * 5
      ) DESC,
      dp.created_at DESC
    LIMIT 5
  ) t;

  SELECT coalesce(
    jsonb_agg(t.obj),
    '[]'::jsonb
  )
  INTO v_top_reels
  FROM (
    SELECT jsonb_build_object(
      'id', r.id,
      'title', coalesce(r.title, ''),
      'thumbnail_url', coalesce(r.thumbnail_url, ''),
      'video_url', coalesce(r.video_url, ''),
      'category', coalesce(r.category, 'Explore'),
      'created_at', r.created_at,
      'views_count', GREATEST(coalesce(r.views_count, 0), coalesce(rv_c.cnt, 0)),
      'likes_count', coalesce(r.likes_count, 0),
      'comments_count', coalesce(r.comments_count, 0),
      'bookmarks_count', coalesce(r.bookmarks_count, 0),
      'shares_count', coalesce(r.shares_count, 0)
    ) AS obj
    FROM public.reels r
    LEFT JOIN LATERAL (
      SELECT count(*)::int AS cnt FROM public.reel_views rv WHERE rv.reel_id = r.id
    ) rv_c ON true
    WHERE r.user_id = v_me
      AND r.deleted_at IS NULL
      AND coalesce(r.is_published, true) = true
    ORDER BY
      (
        GREATEST(coalesce(r.views_count, 0), coalesce(rv_c.cnt, 0))
        + coalesce(r.likes_count, 0) * 3
        + coalesce(r.comments_count, 0) * 4
      ) DESC,
      r.created_at DESC
    LIMIT 5
  ) t;

  SELECT jsonb_build_object(
    'plan_type', coalesce(s.plan_type, s.plan),
    'status', s.status,
    'is_active', coalesce(s.is_active, false),
    'expires_at', s.expires_at
  )
  INTO v_sub
  FROM public.subscriptions s
  WHERE s.user_id = v_me
  LIMIT 1;

  SELECT jsonb_build_object(
    'badge_type', uv.badge_type,
    'status', uv.status,
    'is_active', coalesce(uv.is_active, false),
    'plan_type', uv.plan_type,
    'expires_at', uv.expires_at
  )
  INTO v_verif
  FROM public.user_verifications uv
  WHERE uv.user_id = v_me
  LIMIT 1;

  SELECT jsonb_build_object(
    'has_advertiser', (a.id IS NOT NULL),
    'advertiser_status', coalesce(a.status, 'none'),
    'balance', coalesce(a.balance, 0),
    'campaigns_count', count(c.id)::int,
    'active_campaigns', count(c.id) FILTER (WHERE c.status = 'active')::int,
    'total_impressions', coalesce(sum(c.impressions_count), 0)::bigint,
    'total_clicks', coalesce(sum(c.clicks_count), 0)::bigint,
    'total_spent', coalesce(sum(c.spent_amount), 0)::numeric(14,2)
  )
  INTO v_ads
  FROM public.advertisers a
  LEFT JOIN public.ad_campaigns c ON c.advertiser_id = a.id
  WHERE a.user_id = v_me
  GROUP BY a.id;

  RETURN jsonb_build_object(
    'days', v_days,
    'overview', v_overview,
    'daily_series', v_series,
    'top_posts', v_top_posts,
    'top_reels', v_top_reels,
    'monetization', jsonb_build_object(
      'is_verified', coalesce(v_prof.is_verified, false),
      'referral_count', coalesce(v_prof.referral_count, 0),
      'lifetime_blue_eligible', coalesce(v_prof.lifetime_blue_eligible, false),
      'subscription', v_sub,
      'verification', v_verif,
      'ads', coalesce(
        v_ads,
        jsonb_build_object(
          'has_advertiser', false,
          'advertiser_status', 'none',
          'balance', 0,
          'campaigns_count', 0,
          'active_campaigns', 0,
          'total_impressions', 0,
          'total_clicks', 0,
          'total_spent', 0
        )
      )
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_creator_insights(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_creator_insights(integer) TO authenticated;

-- =============================================================================
-- 5. Account Standing & Restriction Appeals RPC
-- =============================================================================
CREATE OR REPLACE FUNCTION public.submit_restriction_appeal(
  p_reason text,
  p_explanation text,
  p_restriction_id uuid DEFAULT NULL,
  p_evidence_urls text[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_reason text := btrim(coalesce(p_reason, ''));
  v_explanation text := btrim(coalesce(p_explanation, ''));
  v_evidence text[];
  v_row jsonb;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required to submit an appeal.' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_reason) < 3 OR char_length(v_reason) > 200 THEN
    RAISE EXCEPTION 'Appeal reason must be between 3 and 200 characters.' USING ERRCODE = '22023';
  END IF;

  IF char_length(v_explanation) < 10 OR char_length(v_explanation) > 4000 THEN
    RAISE EXCEPTION 'Please provide a clear explanation (at least 10 characters).' USING ERRCODE = '22023';
  END IF;

  IF p_restriction_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.user_restrictions ur
    WHERE ur.id = p_restriction_id AND ur.user_id = v_me
  ) THEN
    RAISE EXCEPTION 'Invalid restriction record selected for this appeal.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.appeals a
    WHERE a.user_id = v_me
      AND a.status IN ('pending', 'under_review')
      AND (
        (p_restriction_id IS NOT NULL AND a.restriction_id = p_restriction_id)
        OR (p_restriction_id IS NULL AND a.restriction_id IS NULL)
      )
  ) THEN
    RAISE EXCEPTION 'You already have an open appeal under review for this notice.' USING ERRCODE = 'P0001';
  END IF;

  SELECT coalesce(array_agg(url), '{}'::text[])
  INTO v_evidence
  FROM (
    SELECT btrim(x) AS url
    FROM unnest(coalesce(p_evidence_urls, '{}'::text[])) AS x
    WHERE btrim(x) <> ''
    LIMIT 5
  ) clean_urls;

  INSERT INTO public.appeals (
    user_id,
    restriction_id,
    reason,
    explanation,
    evidence_urls,
    status
  )
  VALUES (
    v_me,
    p_restriction_id,
    v_reason,
    v_explanation,
    v_evidence,
    'pending'
  )
  RETURNING to_jsonb(appeals.*) INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_restriction_appeal(text, text, uuid, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_restriction_appeal(text, text, uuid, text[]) TO authenticated;

-- =============================================================================
-- 6. Interactive ZEV Live Chat & Presence Rooms (RLS + Realtime + RPCs)
-- =============================================================================
DO $$
DECLARE
  v_tbl text;
BEGIN
  FOREACH v_tbl IN ARRAY ARRAY['live_streams', 'live_comments', 'live_reactions', 'live_viewers', 'appeals']
  LOOP
    BEGIN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_tbl);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    END;
  END LOOP;
END $$;

DROP POLICY IF EXISTS live_streams_select_all ON public.live_streams;
DROP POLICY IF EXISTS live_streams_select_visible ON public.live_streams;
CREATE POLICY live_streams_select_visible ON public.live_streams
  FOR SELECT TO anon, authenticated
  USING (
    auth.uid() = host_id
    OR (
      CASE
        WHEN auth.uid() IS NULL THEN true
        ELSE NOT public.is_blocked_between(auth.uid(), live_streams.host_id)
      END
      AND EXISTS (
        SELECT 1 FROM public.profiles hp
        WHERE hp.id = live_streams.host_id
          AND COALESCE(hp.is_banned, false) = false
          AND COALESCE(hp.account_status, 'active') = 'active'
      )
    )
  );

DROP POLICY IF EXISTS live_comments_select ON public.live_comments;
DROP POLICY IF EXISTS live_comments_select_visible ON public.live_comments;
CREATE POLICY live_comments_select_visible ON public.live_comments
  FOR SELECT TO anon, authenticated
  USING (
    CASE
      WHEN auth.uid() IS NULL THEN true
      ELSE NOT public.is_blocked_between(auth.uid(), live_comments.user_id)
    END
    AND EXISTS (
      SELECT 1 FROM public.profiles cp
      WHERE cp.id = live_comments.user_id
        AND COALESCE(cp.is_banned, false) = false
        AND COALESCE(cp.account_status, 'active') = 'active'
    )
    AND EXISTS (
      SELECT 1 FROM public.live_streams ls
      JOIN public.profiles hp ON hp.id = ls.host_id
      WHERE ls.id = live_comments.stream_id
        AND COALESCE(hp.is_banned, false) = false
        AND COALESCE(hp.account_status, 'active') = 'active'
        AND CASE
              WHEN auth.uid() IS NULL THEN true
              ELSE NOT public.is_blocked_between(auth.uid(), ls.host_id)
            END
    )
  );

DROP POLICY IF EXISTS live_comments_insert ON public.live_comments;
DROP POLICY IF EXISTS live_comments_insert_live ON public.live_comments;
CREATE POLICY live_comments_insert_live ON public.live_comments
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND char_length(btrim(coalesce(comment_text, ''))) BETWEEN 1 AND 500
    AND EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = auth.uid()
        AND COALESCE(me.is_banned, false) = false
        AND COALESCE(me.account_status, 'active') = 'active'
    )
    AND EXISTS (
      SELECT 1 FROM public.live_streams ls
      JOIN public.profiles hp ON hp.id = ls.host_id
      WHERE ls.id = live_comments.stream_id
        AND ls.status = 'live'
        AND COALESCE(hp.is_banned, false) = false
        AND COALESCE(hp.account_status, 'active') = 'active'
        AND NOT public.is_blocked_between(auth.uid(), ls.host_id)
    )
  );

DROP POLICY IF EXISTS live_reactions_select ON public.live_reactions;
DROP POLICY IF EXISTS live_reactions_select_visible ON public.live_reactions;
CREATE POLICY live_reactions_select_visible ON public.live_reactions
  FOR SELECT TO anon, authenticated
  USING (
    CASE
      WHEN auth.uid() IS NULL THEN true
      ELSE NOT public.is_blocked_between(auth.uid(), live_reactions.user_id)
    END
    AND EXISTS (
      SELECT 1 FROM public.live_streams ls
      JOIN public.profiles hp ON hp.id = ls.host_id
      WHERE ls.id = live_reactions.stream_id
        AND COALESCE(hp.is_banned, false) = false
        AND COALESCE(hp.account_status, 'active') = 'active'
        AND CASE
              WHEN auth.uid() IS NULL THEN true
              ELSE NOT public.is_blocked_between(auth.uid(), ls.host_id)
            END
    )
  );

DROP POLICY IF EXISTS live_reactions_insert ON public.live_reactions;
DROP POLICY IF EXISTS live_reactions_insert_live ON public.live_reactions;
CREATE POLICY live_reactions_insert_live ON public.live_reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND char_length(btrim(coalesce(emoji, ''))) BETWEEN 1 AND 16
    AND EXISTS (
      SELECT 1 FROM public.profiles me
      WHERE me.id = auth.uid()
        AND COALESCE(me.is_banned, false) = false
        AND COALESCE(me.account_status, 'active') = 'active'
    )
    AND EXISTS (
      SELECT 1 FROM public.live_streams ls
      JOIN public.profiles hp ON hp.id = ls.host_id
      WHERE ls.id = live_reactions.stream_id
        AND ls.status = 'live'
        AND COALESCE(hp.is_banned, false) = false
        AND COALESCE(hp.account_status, 'active') = 'active'
        AND NOT public.is_blocked_between(auth.uid(), ls.host_id)
    )
  );

DROP POLICY IF EXISTS live_viewers_select ON public.live_viewers;
DROP POLICY IF EXISTS live_viewers_select_visible ON public.live_viewers;
CREATE POLICY live_viewers_select_visible ON public.live_viewers
  FOR SELECT TO authenticated
  USING (
    NOT public.is_blocked_between(auth.uid(), live_viewers.user_id)
    AND EXISTS (
      SELECT 1 FROM public.live_streams ls
      WHERE ls.id = live_viewers.stream_id
        AND NOT public.is_blocked_between(auth.uid(), ls.host_id)
    )
  );

CREATE OR REPLACE FUNCTION public.start_live_stream(
  p_title text,
  p_category text DEFAULT 'General',
  p_thumbnail_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_title text := btrim(coalesce(p_title, ''));
  v_category text := coalesce(nullif(btrim(coalesce(p_category, '')), ''), 'General');
  v_thumb text := nullif(btrim(coalesce(p_thumbnail_url, '')), '');
  v_stream public.live_streams%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = v_me
      AND (COALESCE(p.is_banned, false) = true OR COALESCE(p.account_status, 'active') <> 'active')
  ) THEN
    RAISE EXCEPTION 'Your account standing does not allow hosting live rooms.' USING ERRCODE = '42501';
  END IF;

  IF char_length(v_title) < 2 OR char_length(v_title) > 120 THEN
    RAISE EXCEPTION 'Room title must be between 2 and 120 characters.' USING ERRCODE = '22023';
  END IF;

  -- Cleanly end any stale live room owned by the same host
  UPDATE public.live_streams
  SET status = 'ended',
      ended_at = now(),
      viewer_count = 0,
      updated_at = now()
  WHERE host_id = v_me AND status = 'live';

  INSERT INTO public.live_streams (
    host_id,
    title,
    category,
    thumbnail_url,
    status,
    viewer_count,
    peak_viewer_count,
    started_at,
    updated_at
  )
  VALUES (
    v_me,
    v_title,
    v_category,
    v_thumb,
    'live',
    1,
    1,
    now(),
    now()
  )
  RETURNING * INTO v_stream;

  INSERT INTO public.live_viewers (stream_id, user_id, joined_at, left_at, is_active)
  VALUES (v_stream.id, v_me, now(), NULL, true)
  ON CONFLICT (stream_id, user_id)
  DO UPDATE SET is_active = true, joined_at = now(), left_at = NULL;

  RETURN to_jsonb(v_stream);
END;
$$;

CREATE OR REPLACE FUNCTION public.end_live_stream(p_stream_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_stream public.live_streams%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.live_streams
  SET status = 'ended',
      ended_at = coalesce(ended_at, now()),
      viewer_count = 0,
      updated_at = now()
  WHERE id = p_stream_id
    AND host_id = v_me
  RETURNING * INTO v_stream;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Live room not found or only the host can end it.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.live_viewers
  SET is_active = false,
      left_at = coalesce(left_at, now())
  WHERE stream_id = p_stream_id
    AND is_active = true;

  RETURN to_jsonb(v_stream);
END;
$$;

CREATE OR REPLACE FUNCTION public.join_live_stream(p_stream_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_host uuid;
  v_status text;
  v_cnt integer := 0;
BEGIN
  IF v_me IS NULL OR p_stream_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT ls.host_id, ls.status
  INTO v_host, v_status
  FROM public.live_streams ls
  JOIN public.profiles hp ON hp.id = ls.host_id
  WHERE ls.id = p_stream_id
    AND COALESCE(hp.is_banned, false) = false
    AND COALESCE(hp.account_status, 'active') = 'active';

  IF v_host IS NULL OR v_status <> 'live' THEN
    RAISE EXCEPTION 'This live room has ended or is unavailable.' USING ERRCODE = 'P0001';
  END IF;

  IF v_me <> v_host AND public.is_blocked_between(v_me, v_host) THEN
    RAISE EXCEPTION 'You cannot join this live room.' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.live_viewers (stream_id, user_id, joined_at, left_at, is_active)
  VALUES (p_stream_id, v_me, now(), NULL, true)
  ON CONFLICT (stream_id, user_id)
  DO UPDATE SET is_active = true, joined_at = now(), left_at = NULL;

  SELECT count(*)::integer INTO v_cnt
  FROM public.live_viewers lv
  WHERE lv.stream_id = p_stream_id
    AND lv.is_active = true;

  UPDATE public.live_streams
  SET viewer_count = v_cnt,
      peak_viewer_count = GREATEST(peak_viewer_count, v_cnt),
      updated_at = now()
  WHERE id = p_stream_id;

  RETURN v_cnt;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_live_stream(p_stream_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_cnt integer := 0;
BEGIN
  IF v_me IS NULL OR p_stream_id IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.live_viewers
  SET is_active = false,
      left_at = now()
  WHERE stream_id = p_stream_id
    AND user_id = v_me;

  SELECT count(*)::integer INTO v_cnt
  FROM public.live_viewers lv
  WHERE lv.stream_id = p_stream_id
    AND lv.is_active = true;

  UPDATE public.live_streams
  SET viewer_count = CASE WHEN status = 'live' THEN v_cnt ELSE 0 END,
      updated_at = now()
  WHERE id = p_stream_id;

  RETURN v_cnt;
END;
$$;

REVOKE ALL ON FUNCTION public.start_live_stream(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_live_stream(text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.end_live_stream(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.end_live_stream(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.join_live_stream(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_live_stream(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.leave_live_stream(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leave_live_stream(uuid) TO authenticated;

COMMIT;
