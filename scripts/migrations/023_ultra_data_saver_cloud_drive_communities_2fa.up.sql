-- 023_ultra_data_saver_cloud_drive_communities_2fa.up.sql
-- Migration 023 UP: Ultra Data Saver, Personal Cloud Drive (Saved Messages),
-- Creator Studio (Audience Peaks, Retention & Scheduled Reels),
-- Community Forums (Facebook Groups / Reddit Q&A style),
-- and Advanced Two-Step Verification & Active Session Revocation.

BEGIN;

-- =============================================================================
-- 1. DATA SAVER & BANDWIDTH OPTIMIZATION SETTINGS
-- =============================================================================

ALTER TABLE public.user_settings 
  ADD COLUMN IF NOT EXISTS data_saver_mode text NOT NULL DEFAULT 'off',
  ADD COLUMN IF NOT EXISTS auto_download_media text NOT NULL DEFAULT 'wifi_only',
  ADD COLUMN IF NOT EXISTS video_quality_preference text NOT NULL DEFAULT 'auto',
  ADD COLUMN IF NOT EXISTS image_compression_level text NOT NULL DEFAULT 'standard';

-- =============================================================================
-- 2. PERSONAL CLOUD STORAGE & SAVED MESSAGES (ZEV CLOUD DRIVE)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_cloud_folders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  icon text NOT NULL DEFAULT 'folder',
  color text NOT NULL DEFAULT '0xFF00B2FF',
  items_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_cloud_folder_name UNIQUE (user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_cloud_folders_user ON public.user_cloud_folders (user_id, created_at ASC);

ALTER TABLE public.user_cloud_folders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cloud_folders_owner_all ON public.user_cloud_folders;
CREATE POLICY cloud_folders_owner_all ON public.user_cloud_folders
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.user_cloud_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  folder_id uuid REFERENCES public.user_cloud_folders(id) ON DELETE SET NULL,
  category text NOT NULL DEFAULT 'notes' CHECK (category IN ('notes', 'media', 'documents', 'links', 'audio')),
  title text,
  content text,
  file_url text,
  file_name text,
  file_size bigint NOT NULL DEFAULT 0,
  file_mime_type text,
  thumbnail_url text,
  is_pinned boolean NOT NULL DEFAULT false,
  tags text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cloud_items_user_cat ON public.user_cloud_items (user_id, category, is_pinned DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cloud_items_user_folder ON public.user_cloud_items (user_id, folder_id, created_at DESC);

ALTER TABLE public.user_cloud_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cloud_items_owner_all ON public.user_cloud_items;
CREATE POLICY cloud_items_owner_all ON public.user_cloud_items
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Trigger to keep folder items count updated
CREATE OR REPLACE FUNCTION public.trg_cloud_items_count_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.folder_id IS NOT NULL THEN
    UPDATE public.user_cloud_folders
    SET items_count = items_count + 1, updated_at = now()
    WHERE id = NEW.folder_id;
  ELSIF TG_OP = 'DELETE' AND OLD.folder_id IS NOT NULL THEN
    UPDATE public.user_cloud_folders
    SET items_count = GREATEST(items_count - 1, 0), updated_at = now()
    WHERE id = OLD.folder_id;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.folder_id IS DISTINCT FROM NEW.folder_id THEN
      IF OLD.folder_id IS NOT NULL THEN
        UPDATE public.user_cloud_folders
        SET items_count = GREATEST(items_count - 1, 0), updated_at = now()
        WHERE id = OLD.folder_id;
      END IF;
      IF NEW.folder_id IS NOT NULL THEN
        UPDATE public.user_cloud_folders
        SET items_count = items_count + 1, updated_at = now()
        WHERE id = NEW.folder_id;
      END IF;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cloud_items_count ON public.user_cloud_items;
CREATE TRIGGER trg_cloud_items_count
AFTER INSERT OR UPDATE OF folder_id OR DELETE ON public.user_cloud_items
FOR EACH ROW EXECUTE FUNCTION public.trg_cloud_items_count_func();

-- RPC to get personal cloud storage statistics
CREATE OR REPLACE FUNCTION public.get_user_cloud_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_total_items bigint := 0;
  v_total_bytes bigint := 0;
  v_notes_count bigint := 0;
  v_media_count bigint := 0;
  v_docs_count bigint := 0;
  v_links_count bigint := 0;
  v_audio_count bigint := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT
    count(*),
    coalesce(sum(file_size), 0),
    count(*) FILTER (WHERE category = 'notes'),
    count(*) FILTER (WHERE category = 'media'),
    count(*) FILTER (WHERE category = 'documents'),
    count(*) FILTER (WHERE category = 'links'),
    count(*) FILTER (WHERE category = 'audio')
  INTO
    v_total_items,
    v_total_bytes,
    v_notes_count,
    v_media_count,
    v_docs_count,
    v_links_count,
    v_audio_count
  FROM public.user_cloud_items
  WHERE user_id = v_uid;

  RETURN jsonb_build_object(
    'total_items', v_total_items,
    'total_bytes', v_total_bytes,
    'notes_count', v_notes_count,
    'media_count', v_media_count,
    'documents_count', v_docs_count,
    'links_count', v_links_count,
    'audio_count', v_audio_count
  );
END;
$$;

-- =============================================================================
-- 3. CREATOR STUDIO: AUDIENCE PEAK HOURS & VIDEO RETENTION
-- =============================================================================

ALTER TABLE public.reels
  ADD COLUMN IF NOT EXISTS scheduled_at timestamptz,
  ADD COLUMN IF NOT EXISTS is_draft boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_reels_scheduled_and_drafts
  ON public.reels (user_id, scheduled_at, created_at DESC)
  WHERE deleted_at IS NULL AND (is_draft = true OR scheduled_at IS NOT NULL);

-- Audience Peak Online Hours distribution (0-23 hours) based on follower activity
CREATE OR REPLACE FUNCTION public.get_audience_peak_hours(p_creator_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_creator uuid := coalesce(p_creator_id, auth.uid());
  v_result jsonb;
BEGIN
  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'Creator ID required.' USING ERRCODE = '42501';
  END IF;

  WITH follower_ids AS (
    SELECT follower_id AS uid
    FROM public.user_follows
    WHERE following_id = v_creator
    LIMIT 2000
  ),
  hourly_events AS (
    -- Session activity from followers
    SELECT extract(hour FROM s.last_active_at)::int AS hr, 1 AS weight
    FROM public.user_sessions s
    INNER JOIN follower_ids f ON f.uid = s.user_id
    WHERE s.last_active_at >= now() - interval '30 days'

    UNION ALL

    -- Reel views from followers
    SELECT extract(hour FROM rv.viewed_at)::int AS hr, 2 AS weight
    FROM public.reel_views rv
    INNER JOIN follower_ids f ON f.uid = rv.viewer_id
    WHERE rv.viewed_at >= now() - interval '30 days'

    UNION ALL

    -- Post views from followers
    SELECT extract(hour FROM pv.viewed_at)::int AS hr, 2 AS weight
    FROM public.post_views pv
    INNER JOIN follower_ids f ON f.uid = pv.viewer_id
    WHERE pv.viewed_at >= now() - interval '30 days'
  ),
  hourly_grouped AS (
    SELECT
      h.hour_num,
      coalesce(sum(he.weight), 0) AS raw_score
    FROM generate_series(0, 23) AS h(hour_num)
    LEFT JOIN hourly_events he ON he.hr = h.hour_num
    GROUP BY h.hour_num
    ORDER BY h.hour_num
  ),
  max_score AS (
    SELECT GREATEST(max(raw_score), 1) AS max_val FROM hourly_grouped
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'hour', hg.hour_num,
      'score', round((hg.raw_score::numeric / ms.max_val) * 100),
      'label', to_char((hg.hour_num || ':00')::time, 'FMHH12 AM')
    )
  )
  INTO v_result
  FROM hourly_grouped hg
  CROSS JOIN max_score ms;

  RETURN coalesce(v_result, '[]'::jsonb);
END;
$$;

-- Reel Retention & Watch Time Analytics
CREATE OR REPLACE FUNCTION public.get_reel_retention_analytics(p_reel_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reel public.reels%ROWTYPE;
  v_total_views bigint := 0;
  v_avg_watch_ms numeric := 0;
  v_completion_rate numeric := 0;
  v_duration_ms numeric := 0;
  v_bucket_0_25 bigint := 0;
  v_bucket_25_50 bigint := 0;
  v_bucket_50_75 bigint := 0;
  v_bucket_75_100 bigint := 0;
BEGIN
  SELECT * INTO v_reel FROM public.reels WHERE id = p_reel_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reel not found.' USING ERRCODE = 'P0001';
  END IF;

  v_duration_ms := GREATEST(coalesce(v_reel.duration_seconds, 15) * 1000, 1000);

  SELECT
    count(*),
    coalesce(avg(watch_time_ms), 0),
    count(*) FILTER (WHERE watch_time_ms >= v_duration_ms * 0.9),
    count(*) FILTER (WHERE watch_time_ms < v_duration_ms * 0.25),
    count(*) FILTER (WHERE watch_time_ms >= v_duration_ms * 0.25 AND watch_time_ms < v_duration_ms * 0.50),
    count(*) FILTER (WHERE watch_time_ms >= v_duration_ms * 0.50 AND watch_time_ms < v_duration_ms * 0.75),
    count(*) FILTER (WHERE watch_time_ms >= v_duration_ms * 0.75)
  INTO
    v_total_views,
    v_avg_watch_ms,
    v_completion_rate,
    v_bucket_0_25,
    v_bucket_25_50,
    v_bucket_50_75,
    v_bucket_75_100
  FROM public.reel_views
  WHERE reel_id = p_reel_id;

  RETURN jsonb_build_object(
    'reel_id', p_reel_id,
    'duration_seconds', coalesce(v_reel.duration_seconds, 15),
    'total_views', GREATEST(v_total_views, v_reel.views_count),
    'avg_watch_seconds', round((v_avg_watch_ms / 1000.0), 1),
    'retention_percentage', LEAST(round((v_avg_watch_ms / v_duration_ms) * 100, 1), 100.0),
    'completion_rate', CASE WHEN v_total_views > 0 THEN round((v_completion_rate / v_total_views) * 100, 1) ELSE 0 END,
    'dropoff_curve', jsonb_build_object(
      '0_25', v_bucket_0_25,
      '25_50', v_bucket_25_50,
      '50_75', v_bucket_50_75,
      '75_100', v_bucket_75_100
    )
  );
END;
$$;

-- =============================================================================
-- 4. COMMUNITY FORUMS & GROUPS (FACEBOOK GROUPS / REDDIT Q&A SYSTEM)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.communities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  slug text UNIQUE NOT NULL,
  description text,
  avatar_url text,
  cover_url text,
  category text NOT NULL DEFAULT 'education' CHECK (category IN ('education', 'programming', 'trading', 'technology', 'design', 'business', 'general')),
  is_private boolean NOT NULL DEFAULT false,
  rules text[] NOT NULL DEFAULT '{
    "Respect other members and maintain professional discourse.",
    "No spam, unauthorized advertising, or duplicate posts.",
    "Stay relevant to the group category and learning topic.",
    "Help others and share knowledge constructively."
  }',
  members_count integer NOT NULL DEFAULT 1,
  posts_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_communities_cat ON public.communities (category, members_count DESC);
CREATE INDEX IF NOT EXISTS idx_communities_slug ON public.communities (slug);

ALTER TABLE public.communities ENABLE ROW LEVEL SECURITY;

CREATE POLICY communities_select_public ON public.communities
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY communities_insert_auth ON public.communities
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = creator_id);

CREATE TABLE IF NOT EXISTS public.community_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id uuid NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'moderator', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_community_user UNIQUE (community_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_community_members_user ON public.community_members (user_id, joined_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_members_comm ON public.community_members (community_id, role);

ALTER TABLE public.community_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY community_members_select ON public.community_members
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY community_members_join ON public.community_members
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY community_members_leave ON public.community_members
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY communities_update_admin ON public.communities
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = creator_id
    OR EXISTS (
      SELECT 1 FROM public.community_members
      WHERE community_id = id AND user_id = auth.uid() AND role IN ('admin', 'moderator')
    )
  );

-- Community Posts (Feed posts, Reels, and Questions)
CREATE TABLE IF NOT EXISTS public.community_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id uuid NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  post_type text NOT NULL DEFAULT 'post' CHECK (post_type IN ('post', 'reel', 'question')),
  title text,
  content text NOT NULL,
  media_urls text[] NOT NULL DEFAULT '{}',
  video_url text,
  thumbnail_url text,
  upvotes_count integer NOT NULL DEFAULT 0,
  comments_count integer NOT NULL DEFAULT 0,
  is_pinned boolean NOT NULL DEFAULT false,
  is_solved boolean NOT NULL DEFAULT false,
  best_answer_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_community_posts_comm_pinned ON public.community_posts (community_id, is_pinned DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_posts_type ON public.community_posts (community_id, post_type, created_at DESC);

ALTER TABLE public.community_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY community_posts_select ON public.community_posts
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY community_posts_insert ON public.community_posts
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.community_members
      WHERE community_id = community_posts.community_id AND user_id = auth.uid()
    )
  );

CREATE POLICY community_posts_modify ON public.community_posts
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.community_members
      WHERE community_id = community_posts.community_id AND user_id = auth.uid() AND role IN ('admin', 'moderator')
    )
  );

CREATE POLICY community_posts_delete ON public.community_posts
  FOR DELETE TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.community_members
      WHERE community_id = community_posts.community_id AND user_id = auth.uid() AND role IN ('admin', 'moderator')
    )
  );

-- Post Upvotes / Votes
CREATE TABLE IF NOT EXISTS public.community_post_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.community_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  vote_type smallint NOT NULL CHECK (vote_type IN (1, -1)),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_post_vote UNIQUE (post_id, user_id)
);

ALTER TABLE public.community_post_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY post_votes_select ON public.community_post_votes FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY post_votes_insert_own ON public.community_post_votes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY post_votes_update_own ON public.community_post_votes FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY post_votes_delete_own ON public.community_post_votes FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- Community Comments & Answers
CREATE TABLE IF NOT EXISTS public.community_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.community_posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  parent_id uuid REFERENCES public.community_comments(id) ON DELETE CASCADE,
  content text NOT NULL,
  upvotes_count integer NOT NULL DEFAULT 0,
  is_best_answer boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_comm_comments_post ON public.community_comments (post_id, is_best_answer DESC, upvotes_count DESC, created_at ASC);

ALTER TABLE public.community_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY comm_comments_select ON public.community_comments FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY comm_comments_insert ON public.community_comments FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY comm_comments_modify ON public.community_comments FOR UPDATE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY comm_comments_delete ON public.community_comments FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- Comment Upvotes
CREATE TABLE IF NOT EXISTS public.community_comment_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id uuid NOT NULL REFERENCES public.community_comments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  vote_type smallint NOT NULL CHECK (vote_type IN (1, -1)),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_comment_vote UNIQUE (comment_id, user_id)
);

ALTER TABLE public.community_comment_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY comm_comment_votes_select ON public.community_comment_votes FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY comm_comment_votes_all_own ON public.community_comment_votes FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Membership & Post count triggers
CREATE OR REPLACE FUNCTION public.trg_community_counts_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'community_members' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE public.communities SET members_count = members_count + 1 WHERE id = NEW.community_id;
    ELSIF TG_OP = 'DELETE' THEN
      UPDATE public.communities SET members_count = GREATEST(members_count - 1, 0) WHERE id = OLD.community_id;
    END IF;
  ELSIF TG_TABLE_NAME = 'community_posts' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE public.communities SET posts_count = posts_count + 1 WHERE id = NEW.community_id;
    ELSIF TG_OP = 'DELETE' THEN
      UPDATE public.communities SET posts_count = GREATEST(posts_count - 1, 0) WHERE id = OLD.community_id;
    END IF;
  ELSIF TG_TABLE_NAME = 'community_comments' THEN
    IF TG_OP = 'INSERT' THEN
      UPDATE public.community_posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
      UPDATE public.community_posts SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = OLD.post_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_comm_members_count ON public.community_members;
CREATE TRIGGER trg_comm_members_count
AFTER INSERT OR DELETE ON public.community_members
FOR EACH ROW EXECUTE FUNCTION public.trg_community_counts_func();

DROP TRIGGER IF EXISTS trg_comm_posts_count ON public.community_posts;
CREATE TRIGGER trg_comm_posts_count
AFTER INSERT OR DELETE ON public.community_posts
FOR EACH ROW EXECUTE FUNCTION public.trg_community_counts_func();

DROP TRIGGER IF EXISTS trg_comm_comments_count ON public.community_comments;
CREATE TRIGGER trg_comm_comments_count
AFTER INSERT OR DELETE ON public.community_comments
FOR EACH ROW EXECUTE FUNCTION public.trg_community_counts_func();

-- RPC Functions for Community actions
CREATE OR REPLACE FUNCTION public.vote_community_post(p_post_id uuid, p_vote_type smallint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cur_vote smallint;
  v_net_delta int := 0;
  v_new_total int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT vote_type INTO v_cur_vote
  FROM public.community_post_votes
  WHERE post_id = p_post_id AND user_id = v_uid;

  IF v_cur_vote IS NULL THEN
    INSERT INTO public.community_post_votes (post_id, user_id, vote_type)
    VALUES (p_post_id, v_uid, p_vote_type);
    v_net_delta := p_vote_type;
  ELSIF v_cur_vote = p_vote_type THEN
    DELETE FROM public.community_post_votes
    WHERE post_id = p_post_id AND user_id = v_uid;
    v_net_delta := -p_vote_type;
    p_vote_type := 0;
  ELSE
    UPDATE public.community_post_votes
    SET vote_type = p_vote_type
    WHERE post_id = p_post_id AND user_id = v_uid;
    v_net_delta := p_vote_type * 2;
  END IF;

  UPDATE public.community_posts
  SET upvotes_count = upvotes_count + v_net_delta
  WHERE id = p_post_id
  RETURNING upvotes_count INTO v_new_total;

  RETURN jsonb_build_object(
    'post_id', p_post_id,
    'current_vote', p_vote_type,
    'upvotes_count', v_new_total
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_best_community_answer(p_post_id uuid, p_comment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_post public.community_posts%ROWTYPE;
BEGIN
  SELECT * INTO v_post FROM public.community_posts WHERE id = p_post_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Post not found.' USING ERRCODE = 'P0001';
  END IF;

  IF v_post.user_id != v_uid THEN
    RAISE EXCEPTION 'Only the post author can select the best answer.' USING ERRCODE = '42501';
  END IF;

  -- Clear any previous best answer
  UPDATE public.community_comments
  SET is_best_answer = false
  WHERE post_id = p_post_id;

  -- Mark new best answer
  UPDATE public.community_comments
  SET is_best_answer = true
  WHERE id = p_comment_id AND post_id = p_post_id;

  UPDATE public.community_posts
  SET is_solved = true, best_answer_id = p_comment_id
  WHERE id = p_post_id;

  RETURN jsonb_build_object('success', true, 'best_answer_id', p_comment_id);
END;
$$;

-- =============================================================================
-- 5. TWO-STEP VERIFICATION (2FA) & ACTIVE SESSION REVOCATION
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.user_two_factor_auth (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_enabled boolean NOT NULL DEFAULT false,
  auth_method text NOT NULL DEFAULT 'pin' CHECK (auth_method IN ('pin', 'email', 'totp')),
  pin_hash text,
  totp_secret text,
  backup_codes text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_two_factor_auth ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_two_factor_owner_select ON public.user_two_factor_auth
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Setup 2FA PIN
CREATE OR REPLACE FUNCTION public.setup_two_factor_pin(p_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_salt text;
  v_hash text;
  v_codes text[] := ARRAY[
    substr(md5(random()::text), 1, 8),
    substr(md5(random()::text), 1, 8),
    substr(md5(random()::text), 1, 8),
    substr(md5(random()::text), 1, 8),
    substr(md5(random()::text), 1, 8),
    substr(md5(random()::text), 1, 8)
  ];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  IF length(p_pin) < 4 OR length(p_pin) > 8 THEN
    RAISE EXCEPTION 'PIN must be between 4 and 8 digits.' USING ERRCODE = '22000';
  END IF;

  v_hash := crypt(p_pin, gen_salt('bf', 8));

  INSERT INTO public.user_two_factor_auth (user_id, is_enabled, auth_method, pin_hash, backup_codes, updated_at)
  VALUES (v_uid, true, 'pin', v_hash, v_codes, now())
  ON CONFLICT (user_id) DO UPDATE SET
    is_enabled = true,
    auth_method = 'pin',
    pin_hash = v_hash,
    backup_codes = v_codes,
    updated_at = now();

  INSERT INTO public.user_security_logs (user_id, event_type, status, metadata)
  VALUES (v_uid, '2fa_enabled', 'success', jsonb_build_object('method', 'pin'));

  RETURN jsonb_build_object(
    'success', true,
    'method', 'pin',
    'backup_codes', v_codes
  );
END;
$$;

-- Verify 2FA PIN
CREATE OR REPLACE FUNCTION public.verify_two_factor_pin(p_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_record public.user_two_factor_auth%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_record FROM public.user_two_factor_auth WHERE user_id = v_uid;
  IF NOT FOUND OR NOT v_record.is_enabled THEN
    RETURN jsonb_build_object('valid', true, 'enabled', false);
  END IF;

  IF v_record.pin_hash IS NOT NULL AND v_record.pin_hash = crypt(p_pin, v_record.pin_hash) THEN
    RETURN jsonb_build_object('valid', true, 'enabled', true);
  END IF;

  -- Check backup codes
  IF p_pin = ANY(v_record.backup_codes) THEN
    -- Consume backup code
    UPDATE public.user_two_factor_auth
    SET backup_codes = array_remove(backup_codes, p_pin)
    WHERE user_id = v_uid;

    INSERT INTO public.user_security_logs (user_id, event_type, status, metadata)
    VALUES (v_uid, '2fa_backup_code_used', 'success', '{}'::jsonb);

    RETURN jsonb_build_object('valid', true, 'enabled', true, 'backup_code_used', true);
  END IF;

  RETURN jsonb_build_object('valid', false, 'enabled', true);
END;
$$;

-- Disable 2FA
CREATE OR REPLACE FUNCTION public.disable_two_factor(p_pin text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_check jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  v_check := public.verify_two_factor_pin(p_pin);
  IF (v_check->>'valid')::boolean = false THEN
    RAISE EXCEPTION 'Invalid Security PIN or recovery code.' USING ERRCODE = '42501';
  END IF;

  UPDATE public.user_two_factor_auth
  SET is_enabled = false, pin_hash = NULL, backup_codes = '{}', updated_at = now()
  WHERE user_id = v_uid;

  INSERT INTO public.user_security_logs (user_id, event_type, status, metadata)
  VALUES (v_uid, '2fa_disabled', 'success', '{}'::jsonb);

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Terminate Specific Remote Session
CREATE OR REPLACE FUNCTION public.terminate_user_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.user_sessions
  WHERE id = p_session_id AND user_id = v_uid;

  INSERT INTO public.user_security_logs (user_id, event_type, status, metadata)
  VALUES (v_uid, 'session_terminated', 'success', jsonb_build_object('session_id', p_session_id));

  RETURN jsonb_build_object('success', true, 'session_id', p_session_id);
END;
$$;

-- Terminate All Other Sessions
CREATE OR REPLACE FUNCTION public.terminate_all_other_sessions(p_current_device_id text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  WITH deleted AS (
    DELETE FROM public.user_sessions
    WHERE user_id = v_uid
      AND (p_current_device_id IS NULL OR device_id IS DISTINCT FROM p_current_device_id)
    RETURNING id
  )
  SELECT count(*) INTO v_count FROM deleted;

  INSERT INTO public.user_security_logs (user_id, event_type, status, metadata)
  VALUES (v_uid, 'all_other_sessions_terminated', 'success', jsonb_build_object('revoked_count', v_count));

  RETURN jsonb_build_object('success', true, 'revoked_count', v_count);
END;
$$;

COMMIT;
