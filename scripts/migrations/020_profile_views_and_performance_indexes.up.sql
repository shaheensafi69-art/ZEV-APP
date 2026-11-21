-- 020_profile_views_and_performance_indexes.up.sql
-- 1. Creates profile_views table (TikTok-style 30-day profile view history)
-- 2. Implements record_profile_view(UUID) and get_profile_views_30d() RPCs
-- 3. Enables RLS and Realtime replication on profile_views
-- 4. Creates high-performance composite indexes for feeds, search, and activity

-- 1. Profile Views Table
CREATE TABLE IF NOT EXISTS public.profile_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT profile_views_profile_viewer_key UNIQUE (profile_id, viewer_id)
);

-- 2. Enable RLS
ALTER TABLE public.profile_views ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profile_views' AND policyname = 'profile_views_select_owner_or_viewer'
  ) THEN
    CREATE POLICY profile_views_select_owner_or_viewer ON public.profile_views
      FOR SELECT TO authenticated
      USING (profile_id = auth.uid() OR viewer_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profile_views' AND policyname = 'profile_views_insert_viewer'
  ) THEN
    CREATE POLICY profile_views_insert_viewer ON public.profile_views
      FOR INSERT TO authenticated
      WITH CHECK (viewer_id = auth.uid() AND profile_id <> auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profile_views' AND policyname = 'profile_views_update_viewer'
  ) THEN
    CREATE POLICY profile_views_update_viewer ON public.profile_views
      FOR UPDATE TO authenticated
      USING (viewer_id = auth.uid())
      WITH CHECK (viewer_id = auth.uid());
  END IF;
END $$;

-- 3. RPC: Record Profile View
CREATE OR REPLACE FUNCTION public.record_profile_view(p_profile_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_viewer_id UUID;
BEGIN
  v_viewer_id := auth.uid();
  IF v_viewer_id IS NULL OR v_viewer_id = p_profile_id THEN
    RETURN jsonb_build_object('success', false, 'reason', 'self_or_anonymous');
  END IF;

  INSERT INTO public.profile_views (profile_id, viewer_id, viewed_at)
  VALUES (p_profile_id, v_viewer_id, now())
  ON CONFLICT (profile_id, viewer_id)
  DO UPDATE SET viewed_at = now();

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_profile_view(UUID) TO authenticated;

-- 4. RPC: Get 30-Day Profile Views
CREATE OR REPLACE FUNCTION public.get_profile_views_30d()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_user_id UUID;
  v_result jsonb;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('count', 0, 'viewers', '[]'::jsonb);
  END IF;

  SELECT jsonb_build_object(
    'count', COUNT(pv.id),
    'viewers', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id', pv.id,
        'viewer_id', pv.viewer_id,
        'username', p.username,
        'first_name', p.first_name,
        'last_name', p.last_name,
        'full_name', TRIM(CONCAT(p.first_name, ' ', p.last_name)),
        'avatar_url', p.avatar_url,
        'is_verified', COALESCE(p.is_verified, false),
        'viewed_at', pv.viewed_at,
        'is_following', EXISTS(
          SELECT 1 FROM public.user_follows uf
          WHERE uf.follower_id = v_user_id AND uf.following_id = pv.viewer_id
        )
      ) ORDER BY pv.viewed_at DESC
    ), '[]'::jsonb)
  )
  INTO v_result
  FROM public.profile_views pv
  JOIN public.profiles p ON p.id = pv.viewer_id
  WHERE pv.profile_id = v_user_id
    AND pv.viewed_at >= (now() - interval '30 days');

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_profile_views_30d() TO authenticated;

-- 5. Realtime Publication
ALTER TABLE public.profile_views REPLICA IDENTITY FULL;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.profile_views;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 6. Performance Composite Indexes
CREATE INDEX IF NOT EXISTS idx_profile_views_profile_viewed_at
  ON public.profile_views (profile_id, viewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_profile_views_viewer_viewed_at
  ON public.profile_views (viewer_id, viewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_discussion_posts_created_at_id
  ON public.discussion_posts (created_at DESC, id DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_reels_created_at_id
  ON public.reels (created_at DESC, id DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_follows_follower_following
  ON public.user_follows (follower_id, following_id);

CREATE INDEX IF NOT EXISTS idx_user_follows_following_follower
  ON public.user_follows (following_id, follower_id);

CREATE INDEX IF NOT EXISTS idx_user_notifications_user_created
  ON public.user_notifications (user_id, created_at DESC);
