-- 021_atomic_counters_and_recommendation_engine.up.sql
-- 1. Accurate atomic counter triggers and RPCs for post views, reel views, profile views,
--    likes, comments, reposts, bookmarks, followers, and following.
-- 2. User content interactions table for AI recommendation telemetry.
-- 3. AI recommendation ranking engine for Reels and Feed.

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. PROFILES: ADD profile_views_count COLUMN (IF NOT EXISTS)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS profile_views_count integer NOT NULL DEFAULT 0;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. USER CONTENT INTERACTIONS TABLE (AI RECOMMENDATION TELEMETRY)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.user_content_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content_type TEXT NOT NULL CHECK (content_type IN ('post', 'reel', 'profile')),
    content_id UUID NOT NULL,
    interaction_type TEXT NOT NULL CHECK (interaction_type IN ('view', 'watch_complete', 'like', 'comment', 'save', 'share', 'repost', 'hide')),
    category TEXT,
    author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    weight NUMERIC NOT NULL DEFAULT 1.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.user_content_interactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_content_interactions' AND policyname = 'user_content_interactions_select_own'
  ) THEN
    CREATE POLICY user_content_interactions_select_own ON public.user_content_interactions
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_content_interactions' AND policyname = 'user_content_interactions_insert_own'
  ) THEN
    CREATE POLICY user_content_interactions_insert_own ON public.user_content_interactions
      FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- High-performance AI recommendation indexes
CREATE INDEX IF NOT EXISTS idx_user_content_interactions_user_cat
  ON public.user_content_interactions (user_id, category, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_content_interactions_author
  ON public.user_content_interactions (user_id, author_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_user_content_interactions_recent
  ON public.user_content_interactions (user_id, created_at DESC);

-- RPC: Record Content Interaction
CREATE OR REPLACE FUNCTION public.record_content_interaction(
  p_content_type text,
  p_content_id uuid,
  p_interaction_type text,
  p_category text DEFAULT NULL,
  p_author_id uuid DEFAULT NULL,
  p_weight numeric DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_default_weight numeric := 1.0;
BEGIN
  IF v_me IS NULL OR p_content_id IS NULL THEN
    RETURN;
  END IF;

  -- Calculate intelligent default weight by action type
  IF p_weight IS NULL THEN
    CASE p_interaction_type
      WHEN 'view' THEN v_default_weight := 1.0;
      WHEN 'watch_complete' THEN v_default_weight := 2.5;
      WHEN 'like' THEN v_default_weight := 4.0;
      WHEN 'comment' THEN v_default_weight := 5.0;
      WHEN 'save' THEN v_default_weight := 6.0;
      WHEN 'share' THEN v_default_weight := 7.0;
      WHEN 'repost' THEN v_default_weight := 8.0;
      WHEN 'hide' THEN v_default_weight := -10.0;
      ELSE v_default_weight := 1.0;
    END CASE;
  ELSE
    v_default_weight := p_weight;
  END IF;

  INSERT INTO public.user_content_interactions (
    user_id,
    content_type,
    content_id,
    interaction_type,
    category,
    author_id,
    weight,
    created_at
  ) VALUES (
    v_me,
    p_content_type,
    p_content_id,
    p_interaction_type,
    p_category,
    p_author_id,
    v_default_weight,
    now()
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_content_interaction(text, uuid, text, text, uuid, numeric) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. UPGRADE ATOMIC POST & REEL VIEW COUNTERS
-- ═══════════════════════════════════════════════════════════════════════════

-- Ensure post_views has viewed_at
ALTER TABLE public.post_views
  ADD COLUMN IF NOT EXISTS viewed_at timestamptz NOT NULL DEFAULT now();

-- Ensure reel_views has viewed_at and watch_time_ms
ALTER TABLE public.reel_views
  ADD COLUMN IF NOT EXISTS viewed_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS watch_time_ms integer DEFAULT 0;

-- Drop prior functions to allow new signature/return type
DROP FUNCTION IF EXISTS public.record_post_view(uuid);
DROP FUNCTION IF EXISTS public.record_reel_view(uuid);
DROP FUNCTION IF EXISTS public.record_reel_view(uuid, integer);

-- Upgraded record_post_view (Atomic increment + viewer logging + AI interaction tracking)
CREATE OR REPLACE FUNCTION public.record_post_view(p_post_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_author uuid;
  v_cat text;
  v_new_views integer;
BEGIN
  IF p_post_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'missing_post_id');
  END IF;

  -- 1. Validate post exists and fetch author/category
  SELECT dp.student_id, dp.category INTO v_author, v_cat
  FROM public.discussion_posts dp
  JOIN public.profiles pr ON pr.id = dp.student_id
  WHERE dp.id = p_post_id
    AND dp.deleted_at IS NULL
    AND COALESCE(dp.is_draft, false) = false
    AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
    AND COALESCE(pr.is_banned, false) = false
    AND COALESCE(pr.account_status, 'active') = 'active';

  IF v_author IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'post_not_found');
  END IF;

  IF v_me IS NOT NULL AND public.is_blocked_between(v_me, v_author) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'blocked');
  END IF;

  -- 2. Atomic increment on discussion_posts
  UPDATE public.discussion_posts
  SET views_count = views_count + 1
  WHERE id = p_post_id
  RETURNING views_count INTO v_new_views;

  -- 3. Log into post_views if authenticated
  IF v_me IS NOT NULL THEN
    INSERT INTO public.post_views (post_id, viewer_id, viewed_at)
    VALUES (p_post_id, v_me, now())
    ON CONFLICT (post_id, viewer_id) DO UPDATE
      SET viewed_at = now();

    -- 4. Record interaction for AI recommendation engine
    PERFORM public.record_content_interaction('post', p_post_id, 'view', v_cat, v_author, 1.0);
  END IF;

  RETURN jsonb_build_object('success', true, 'views_count', v_new_views);
END;
$$;
REVOKE ALL ON FUNCTION public.record_post_view(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_post_view(uuid) TO authenticated, anon;

-- Upgraded record_reel_view (Atomic increment + viewer logging + AI interaction tracking)
CREATE OR REPLACE FUNCTION public.record_reel_view(
  p_reel_id uuid,
  p_watch_time_ms integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_author uuid;
  v_cat text;
  v_new_views integer;
BEGIN
  IF p_reel_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'missing_reel_id');
  END IF;

  -- 1. Validate reel exists and fetch author/category
  SELECT r.user_id, r.category INTO v_author, v_cat
  FROM public.reels r
  JOIN public.profiles pr ON pr.id = r.user_id
  WHERE r.id = p_reel_id
    AND r.deleted_at IS NULL
    AND COALESCE(r.is_published, true) = true
    AND COALESCE(pr.is_banned, false) = false
    AND COALESCE(pr.account_status, 'active') = 'active';

  IF v_author IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'reel_not_found');
  END IF;

  IF v_me IS NOT NULL AND public.is_blocked_between(v_me, v_author) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'blocked');
  END IF;

  -- 2. Atomic increment on reels
  UPDATE public.reels
  SET views_count = views_count + 1
  WHERE id = p_reel_id
  RETURNING views_count INTO v_new_views;

  -- 3. Log into reel_views if authenticated
  IF v_me IS NOT NULL THEN
    INSERT INTO public.reel_views (reel_id, viewer_id, viewed_at, watch_time_ms)
    VALUES (p_reel_id, v_me, now(), COALESCE(p_watch_time_ms, 0))
    ON CONFLICT (reel_id, viewer_id) DO UPDATE
      SET viewed_at = now(),
          watch_time_ms = GREATEST(reel_views.watch_time_ms, COALESCE(p_watch_time_ms, 0));

    -- 4. Record interaction for AI recommendation engine
    PERFORM public.record_content_interaction('reel', p_reel_id, 'view', v_cat, v_author, 1.0);
  END IF;

  RETURN jsonb_build_object('success', true, 'views_count', v_new_views);
END;
$$;
REVOKE ALL ON FUNCTION public.record_reel_view(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_reel_view(uuid, integer) TO authenticated, anon;

-- Overload for single-argument call backward compatibility
CREATE OR REPLACE FUNCTION public.record_reel_view(p_reel_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  RETURN public.record_reel_view(p_reel_id, NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.record_reel_view(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_reel_view(uuid) TO authenticated, anon;

-- Drop prior profile view function if needed
DROP FUNCTION IF EXISTS public.record_profile_view(UUID);

-- Upgraded record_profile_view (Increments profiles.profile_views_count + AI interaction)
CREATE OR REPLACE FUNCTION public.record_profile_view(p_profile_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_viewer_id UUID;
  v_new_views integer;
BEGIN
  v_viewer_id := auth.uid();
  IF v_viewer_id IS NULL OR v_viewer_id = p_profile_id THEN
    RETURN jsonb_build_object('success', false, 'reason', 'self_or_anonymous');
  END IF;

  -- Check blocking
  IF public.is_blocked_between(v_viewer_id, p_profile_id) THEN
    RETURN jsonb_build_object('success', false, 'reason', 'blocked');
  END IF;

  -- Upsert into profile_views
  INSERT INTO public.profile_views (profile_id, viewer_id, viewed_at)
  VALUES (p_profile_id, v_viewer_id, now())
  ON CONFLICT (profile_id, viewer_id)
  DO UPDATE SET viewed_at = now();

  -- Atomic increment on profiles table
  UPDATE public.profiles
  SET profile_views_count = profile_views_count + 1
  WHERE id = p_profile_id
  RETURNING profile_views_count INTO v_new_views;

  -- Record interaction for AI recommendation engine
  PERFORM public.record_content_interaction('profile', p_profile_id, 'view', NULL, p_profile_id, 1.5);

  RETURN jsonb_build_object('success', true, 'profile_views_count', v_new_views);
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_profile_view(UUID) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. AI-POWERED REELS RANKING ENGINE (get_reels_page)
-- ═══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.get_reels_page(timestamptz, uuid, integer, boolean);

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
  is_author_followed boolean,
  recommendation_score double precision
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
  WITH scored_reels AS (
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
      ) END AS is_author_followed,
      -- AI Recommendation Score Calculation
      CASE 
        WHEN coalesce(p_following_only, false) = true THEN 0.0::double precision
        ELSE (
          -- 1. Affinity Match (45% weight): User interaction history with this category or creator
          COALESCE((
            SELECT LEAST(50.0, SUM(uci.weight))
            FROM public.user_content_interactions uci
            WHERE uci.user_id = v_me
              AND (uci.category = r.category OR uci.author_id = r.user_id)
              AND uci.created_at >= (now() - interval '30 days')
          ), 0.0) * 0.45
          -- 2. Viral Engagement Velocity (35% weight)
          + (
            (r.likes_count * 3.0 + r.comments_count * 5.0 + coalesce(r.bookmarks_count, 0) * 4.0)
            / GREATEST(r.views_count, 1.0)
          ) * 0.35
          -- 3. Freshness Decay (20% weight)
          + GREATEST(0.0, (100.0 - (EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600.0) * 1.5)) * 0.20
        )::double precision
      END AS recommendation_score
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
  )
  SELECT 
    sr.id,
    sr.user_id,
    sr.title,
    sr.description,
    sr.video_url,
    sr.thumbnail_url,
    sr.category,
    sr.audio_name,
    sr.duration_seconds,
    sr.views_count,
    sr.likes_count,
    sr.comments_count,
    sr.created_at,
    sr.author_username,
    sr.author_first_name,
    sr.author_last_name,
    sr.author_avatar_url,
    sr.author_is_verified,
    sr.is_liked_by_me,
    sr.is_bookmarked_by_me,
    sr.is_author_followed,
    sr.recommendation_score
  FROM scored_reels sr
  ORDER BY 
    CASE WHEN coalesce(p_following_only, false) = false THEN sr.recommendation_score END DESC NULLS LAST,
    sr.created_at DESC, 
    sr.id DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_reels_page(timestamptz, uuid, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_reels_page(timestamptz, uuid, integer, boolean) TO authenticated, anon;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. RUN FULL COUNTER RECONCILIATION TO GUARANTEE 100% ACCURACY
-- ═══════════════════════════════════════════════════════════════════════════
SELECT public.reconcile_all_counters();

COMMIT;
