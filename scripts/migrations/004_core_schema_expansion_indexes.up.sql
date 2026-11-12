-- 004_core_schema_expansion_indexes.up.sql
-- Expand existing core ZEV tables backward-compatibly, create missing normalized
-- account/social/content/chat/ads/live tables with explicit RLS policies + FKs,
-- backfill direct conversations, and add high-value composite/partial/FTS indexes.

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. EXPAND EXISTING TABLES (Zero breaking renames; zev_admin compatible)
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_private boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_banned boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS banned_until timestamptz,
  ADD COLUMN IF NOT EXISTS ban_reason text,
  ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS location text,
  ADD COLUMN IF NOT EXISTS username_changed_at timestamptz,
  ADD COLUMN IF NOT EXISTS followers_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS following_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS posts_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reels_count integer NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.protect_profile_privileged_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin')
     OR COALESCE(auth.role(), '') = 'service_role'
     OR public.is_app_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.is_verified IS DISTINCT FROM OLD.is_verified
     OR NEW.lifetime_blue_eligible IS DISTINCT FROM OLD.lifetime_blue_eligible
     OR NEW.referral_count IS DISTINCT FROM OLD.referral_count
     OR NEW.referred_by IS DISTINCT FROM OLD.referred_by
     OR NEW.is_restricted IS DISTINCT FROM OLD.is_restricted
     OR NEW.restricted_until IS DISTINCT FROM OLD.restricted_until
     OR NEW.restriction_reason IS DISTINCT FROM OLD.restriction_reason
     OR NEW.warning_count IS DISTINCT FROM OLD.warning_count
     OR NEW.last_warning_at IS DISTINCT FROM OLD.last_warning_at
     OR NEW.last_warning_reason IS DISTINCT FROM OLD.last_warning_reason
     OR NEW.is_banned IS DISTINCT FROM OLD.is_banned
     OR NEW.banned_until IS DISTINCT FROM OLD.banned_until
     OR NEW.ban_reason IS DISTINCT FROM OLD.ban_reason
     OR NEW.account_status IS DISTINCT FROM OLD.account_status
     OR NEW.followers_count IS DISTINCT FROM OLD.followers_count
     OR NEW.following_count IS DISTINCT FROM OLD.following_count
     OR NEW.posts_count IS DISTINCT FROM OLD.posts_count
     OR NEW.reels_count IS DISTINCT FROM OLD.reels_count THEN
    RAISE EXCEPTION 'Insufficient privileges to modify protected profile attributes'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

ALTER TABLE public.discussion_posts
  ADD COLUMN IF NOT EXISTS post_type text NOT NULL DEFAULT 'post',
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS comments_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS likes_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS comments_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reposts_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bookmarks_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS views_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS location text,
  ADD COLUMN IF NOT EXISTS is_draft boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS scheduled_at timestamptz,
  ADD COLUMN IF NOT EXISTS published_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS edited_at timestamptz,
  ADD COLUMN IF NOT EXISTS collaborator_ids uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS tagged_user_ids uuid[] NOT NULL DEFAULT '{}';

ALTER TABLE public.discussion_comments
  ADD COLUMN IF NOT EXISTS likes_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_pinned boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS edited_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.reel_comments
  ADD COLUMN IF NOT EXISTS parent_comment_id uuid REFERENCES public.reel_comments(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS likes_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_pinned boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS edited_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.reels
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS comments_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS bookmarks_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS shares_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS edited_at timestamptz,
  ADD COLUMN IF NOT EXISTS audio_name text;

ALTER TABLE public.user_stories
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public',
  ADD COLUMN IF NOT EXISTS views_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS likes_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS replies_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

ALTER TABLE public.direct_messages
  ALTER COLUMN receiver_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS conversation_id uuid,
  ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text',
  ADD COLUMN IF NOT EXISTS reply_to_message_id uuid REFERENCES public.direct_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS forwarded_from_id uuid,
  ADD COLUMN IF NOT EXISTS edited_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz,
  ADD COLUMN IF NOT EXISTS deleted_for_user_ids uuid[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS file_name text,
  ADD COLUMN IF NOT EXISTS file_size bigint,
  ADD COLUMN IF NOT EXISTS mime_type text;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. ACCOUNT, PRIVACY, SETTINGS, SECURITY, LINKS, NOTIFICATIONS TABLES
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  theme_mode text NOT NULL DEFAULT 'light',
  auto_play_videos boolean NOT NULL DEFAULT true,
  data_saver boolean NOT NULL DEFAULT false,
  show_read_receipts boolean NOT NULL DEFAULT true,
  show_activity_status boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_settings_own_all ON public.user_settings
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.user_privacy_settings (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  is_private_account boolean NOT NULL DEFAULT false,
  allow_messages_from text NOT NULL DEFAULT 'everyone',
  allow_mentions_from text NOT NULL DEFAULT 'everyone',
  allow_tags_from text NOT NULL DEFAULT 'everyone',
  allow_story_replies_from text NOT NULL DEFAULT 'everyone',
  hide_online_status boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_privacy_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_privacy_own_all ON public.user_privacy_settings
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  interests text[] NOT NULL DEFAULT '{}',
  preferred_categories text[] NOT NULL DEFAULT '{}',
  muted_keywords text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_preferences_own_all ON public.user_preferences
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  device_id text,
  platform text,
  device_name text,
  app_version text,
  ip_address text,
  user_agent text,
  is_active boolean NOT NULL DEFAULT true,
  started_at timestamptz NOT NULL DEFAULT now(),
  last_active_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  duration_seconds integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_active ON public.user_sessions (user_id, last_active_at DESC);
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_sessions_own_all ON public.user_sessions
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.user_security_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  status text NOT NULL DEFAULT 'success',
  ip_address text,
  device_id text,
  platform text,
  user_agent text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_user_security_logs_user_created ON public.user_security_logs (user_id, created_at DESC);
ALTER TABLE public.user_security_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_security_logs_select_own ON public.user_security_logs
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY user_security_logs_insert_own ON public.user_security_logs
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.user_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title text NOT NULL,
  url text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_user_links_user ON public.user_links (user_id, sort_order ASC);
ALTER TABLE public.user_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_links_select_all ON public.user_links FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY user_links_manage_own ON public.user_links FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.account_deletions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  reason text,
  action_type text NOT NULL DEFAULT 'delete',
  status text NOT NULL DEFAULT 'requested',
  requested_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.account_deletions ENABLE ROW LEVEL SECURITY;
CREATE POLICY account_deletions_select_own ON public.account_deletions
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  push_enabled boolean NOT NULL DEFAULT true,
  pause_all boolean NOT NULL DEFAULT false,
  messages_enabled boolean NOT NULL DEFAULT true,
  likes_enabled boolean NOT NULL DEFAULT true,
  comments_enabled boolean NOT NULL DEFAULT true,
  follows_enabled boolean NOT NULL DEFAULT true,
  mentions_enabled boolean NOT NULL DEFAULT true,
  stories_enabled boolean NOT NULL DEFAULT true,
  live_enabled boolean NOT NULL DEFAULT true,
  marketing_enabled boolean NOT NULL DEFAULT false,
  quiet_hours_start text,
  quiet_hours_end text,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY notification_prefs_own_all ON public.notification_preferences
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.notification_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  notification_type text NOT NULL,
  status text NOT NULL,
  tokens_targeted integer NOT NULL DEFAULT 0,
  sent_count integer NOT NULL DEFAULT 0,
  failed_count integer NOT NULL DEFAULT 0,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_user ON public.notification_deliveries (user_id, created_at DESC);
ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;
CREATE POLICY notification_deliveries_select_own ON public.notification_deliveries
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. SOCIAL GRAPH EXTENSIONS
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.follow_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_follow_requests_pair UNIQUE (requester_id, target_id),
  CONSTRAINT chk_follow_requests_no_self CHECK (requester_id <> target_id),
  CONSTRAINT chk_follow_requests_status CHECK (status IN ('pending', 'accepted', 'rejected'))
);
CREATE INDEX IF NOT EXISTS idx_follow_requests_target_pending ON public.follow_requests (target_id, created_at DESC) WHERE status = 'pending';
ALTER TABLE public.follow_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY follow_requests_select ON public.follow_requests
  FOR SELECT TO authenticated USING (auth.uid() = requester_id OR auth.uid() = target_id);
CREATE POLICY follow_requests_insert ON public.follow_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = requester_id
    AND requester_id <> target_id
    AND status = 'pending'
    AND NOT public.is_blocked_between(requester_id, target_id)
  );
CREATE POLICY follow_requests_update_target ON public.follow_requests
  FOR UPDATE TO authenticated
  USING (auth.uid() = target_id) WITH CHECK (auth.uid() = target_id);
CREATE POLICY follow_requests_delete_participant ON public.follow_requests
  FOR DELETE TO authenticated
  USING (auth.uid() = requester_id OR auth.uid() = target_id);

CREATE TABLE IF NOT EXISTS public.close_friends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  friend_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_close_friends_pair UNIQUE (user_id, friend_id),
  CONSTRAINT chk_close_friends_no_self CHECK (user_id <> friend_id)
);
CREATE INDEX IF NOT EXISTS idx_close_friends_friend ON public.close_friends (friend_id, user_id);
ALTER TABLE public.close_friends ENABLE ROW LEVEL SECURITY;
CREATE POLICY close_friends_select ON public.close_friends
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR auth.uid() = friend_id);
CREATE POLICY close_friends_manage_own ON public.close_friends
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.user_mutes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  muter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  muted_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  mute_posts boolean NOT NULL DEFAULT true,
  mute_stories boolean NOT NULL DEFAULT true,
  mute_messages boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_mutes_pair UNIQUE (muter_id, muted_id),
  CONSTRAINT chk_user_mutes_no_self CHECK (muter_id <> muted_id)
);
ALTER TABLE public.user_mutes ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_mutes_own_all ON public.user_mutes
  FOR ALL TO authenticated USING (auth.uid() = muter_id) WITH CHECK (auth.uid() = muter_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. CONTENT, MEDIA, MODERATION, SEARCH & STORIES EXTENSIONS
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.post_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.discussion_posts(id) ON DELETE CASCADE,
  media_type text NOT NULL DEFAULT 'image',
  media_url text NOT NULL,
  r2_key text,
  thumbnail_url text,
  width integer,
  height integer,
  duration_seconds integer,
  file_size bigint,
  mime_type text,
  processing_status text NOT NULL DEFAULT 'ready',
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_post_media_post_sort ON public.post_media (post_id, sort_order ASC);
ALTER TABLE public.post_media ENABLE ROW LEVEL SECURITY;
CREATE POLICY post_media_select_all ON public.post_media FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY post_media_insert_owner ON public.post_media
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = post_id AND p.student_id = auth.uid()));
CREATE POLICY post_media_update_owner ON public.post_media
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = post_id AND p.student_id = auth.uid()));
CREATE POLICY post_media_delete_owner ON public.post_media
  FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = post_id AND p.student_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.comment_likes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id uuid NOT NULL,
  comment_type text NOT NULL DEFAULT 'post' CHECK (comment_type IN ('post', 'reel')),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_comment_likes UNIQUE (comment_id, comment_type, user_id)
);
CREATE INDEX IF NOT EXISTS idx_comment_likes_comment ON public.comment_likes (comment_id, comment_type);
ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY comment_likes_select_all ON public.comment_likes FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY comment_likes_insert_own ON public.comment_likes FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY comment_likes_delete_own ON public.comment_likes FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.comment_pins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id uuid NOT NULL,
  target_type text NOT NULL DEFAULT 'post' CHECK (target_type IN ('post', 'reel')),
  comment_id uuid NOT NULL,
  pinned_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_comment_pins UNIQUE (target_id, target_type, comment_id)
);
ALTER TABLE public.comment_pins ENABLE ROW LEVEL SECURITY;
CREATE POLICY comment_pins_select_all ON public.comment_pins FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY comment_pins_manage_owner ON public.comment_pins
  FOR ALL TO authenticated
  USING (
    auth.uid() = pinned_by
    AND (
      (target_type = 'post' AND EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = target_id AND p.student_id = auth.uid()))
      OR
      (target_type = 'reel' AND EXISTS (SELECT 1 FROM public.reels r WHERE r.id = target_id AND r.user_id = auth.uid()))
    )
  )
  WITH CHECK (
    auth.uid() = pinned_by
    AND (
      (target_type = 'post' AND EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = target_id AND p.student_id = auth.uid()))
      OR
      (target_type = 'reel' AND EXISTS (SELECT 1 FROM public.reels r WHERE r.id = target_id AND r.user_id = auth.uid()))
    )
  );

CREATE TABLE IF NOT EXISTS public.post_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.discussion_posts(id) ON DELETE CASCADE,
  viewer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_post_views_pair UNIQUE (post_id, viewer_id)
);
ALTER TABLE public.post_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY post_views_select_own ON public.post_views
  FOR SELECT TO authenticated
  USING (
    auth.uid() = viewer_id
    OR EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = post_id AND p.student_id = auth.uid())
  );
CREATE POLICY post_views_insert_own ON public.post_views
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = viewer_id);

CREATE TABLE IF NOT EXISTS public.post_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_type text NOT NULL DEFAULT 'post' CHECK (target_type IN ('post', 'reel', 'comment', 'story', 'message')),
  target_id uuid NOT NULL,
  reported_user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  reason text NOT NULL,
  details text,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_post_reports_status ON public.post_reports (status, created_at DESC);
ALTER TABLE public.post_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY post_reports_insert_own ON public.post_reports FOR INSERT TO authenticated WITH CHECK (auth.uid() = reporter_id);
CREATE POLICY post_reports_select_own ON public.post_reports FOR SELECT TO authenticated USING (auth.uid() = reporter_id OR public.is_app_admin());

CREATE TABLE IF NOT EXISTS public.hidden_posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_type text NOT NULL DEFAULT 'post' CHECK (target_type IN ('post', 'reel')),
  target_id uuid NOT NULL,
  reason text NOT NULL DEFAULT 'not_interested',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_hidden_posts UNIQUE (user_id, target_type, target_id)
);
CREATE INDEX IF NOT EXISTS idx_hidden_posts_user ON public.hidden_posts (user_id, target_type);
ALTER TABLE public.hidden_posts ENABLE ROW LEVEL SECURITY;
CREATE POLICY hidden_posts_own_all ON public.hidden_posts
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.media_deletion_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  r2_key text NOT NULL,
  media_url text,
  reason text NOT NULL DEFAULT 'content_deleted',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed')),
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  next_retry_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_media_deletion_queue_pending ON public.media_deletion_queue (status, next_retry_at) WHERE status <> 'completed';
ALTER TABLE public.media_deletion_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY media_deletion_queue_select_own ON public.media_deletion_queue
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_app_admin());
CREATE POLICY media_deletion_queue_insert_own ON public.media_deletion_queue
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.story_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.user_stories(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_story_reactions_story ON public.story_reactions (story_id, created_at DESC);
ALTER TABLE public.story_reactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY story_reactions_select ON public.story_reactions
  FOR SELECT TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (SELECT 1 FROM public.user_stories s WHERE s.id = story_id AND s.user_id = auth.uid())
  );
CREATE POLICY story_reactions_insert ON public.story_reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM public.user_stories s WHERE s.id = story_id AND NOT public.is_blocked_between(auth.uid(), s.user_id))
  );

CREATE TABLE IF NOT EXISTS public.story_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  story_id uuid NOT NULL REFERENCES public.user_stories(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reply_text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_story_replies_story ON public.story_replies (story_id, created_at DESC);
ALTER TABLE public.story_replies ENABLE ROW LEVEL SECURITY;
CREATE POLICY story_replies_select ON public.story_replies
  FOR SELECT TO authenticated
  USING (
    auth.uid() = sender_id
    OR EXISTS (SELECT 1 FROM public.user_stories s WHERE s.id = story_id AND s.user_id = auth.uid())
  );
CREATE POLICY story_replies_insert ON public.story_replies
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND EXISTS (SELECT 1 FROM public.user_stories s WHERE s.id = story_id AND NOT public.is_blocked_between(auth.uid(), s.user_id))
  );

CREATE TABLE IF NOT EXISTS public.story_mutes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  muted_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_story_mutes UNIQUE (user_id, muted_user_id),
  CONSTRAINT chk_story_mutes_no_self CHECK (user_id <> muted_user_id)
);
ALTER TABLE public.story_mutes ENABLE ROW LEVEL SECURITY;
CREATE POLICY story_mutes_own_all ON public.story_mutes
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.search_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  query text NOT NULL,
  search_type text NOT NULL DEFAULT 'all',
  target_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_search_history_entry UNIQUE (user_id, query, search_type)
);
CREATE INDEX IF NOT EXISTS idx_search_history_user_recent ON public.search_history (user_id, updated_at DESC);
ALTER TABLE public.search_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY search_history_own_all ON public.search_history
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.trending_topics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic text NOT NULL UNIQUE,
  category text NOT NULL DEFAULT 'general',
  score numeric NOT NULL DEFAULT 0,
  posts_count integer NOT NULL DEFAULT 0,
  reels_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.trending_topics ENABLE ROW LEVEL SECURITY;
CREATE POLICY trending_topics_select_all ON public.trending_topics FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.appeals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  restriction_id uuid REFERENCES public.user_restrictions(id) ON DELETE SET NULL,
  reason text NOT NULL,
  explanation text NOT NULL,
  evidence_urls text[] NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'rejected')),
  admin_response text,
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_appeals_user ON public.appeals (user_id, created_at DESC);
ALTER TABLE public.appeals ENABLE ROW LEVEL SECURITY;
CREATE POLICY appeals_select_own ON public.appeals
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_app_admin());
CREATE POLICY appeals_insert_own ON public.appeals
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND status = 'pending');

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. CHAT & GROUP CONVERSATIONS EXTENSIONS (Anti-recursion SECURITY DEFINER helpers)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_group boolean NOT NULL DEFAULT false,
  direct_key text UNIQUE,
  title text,
  avatar_url text,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  last_message_text text,
  last_message_type text,
  last_message_at timestamptz,
  last_sender_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_conversations_last_msg ON public.conversations (last_message_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS public.conversation_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  last_read_at timestamptz,
  CONSTRAINT uq_conversation_members UNIQUE (conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user ON public.conversation_members (user_id, conversation_id);

CREATE OR REPLACE FUNCTION public.is_conversation_member(
  p_conversation_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members cm
    WHERE cm.conversation_id = p_conversation_id
      AND cm.user_id = p_user_id
  );
$$;

CREATE OR REPLACE FUNCTION public.is_conversation_admin(
  p_conversation_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_members cm
    WHERE cm.conversation_id = p_conversation_id
      AND cm.user_id = p_user_id
      AND cm.role = 'admin'
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_conversation_member(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_admin(uuid, uuid) TO authenticated;

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY conversations_select_member ON public.conversations
  FOR SELECT TO authenticated
  USING (public.is_conversation_member(id) OR created_by = auth.uid());
CREATE POLICY conversations_insert_auth ON public.conversations
  FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());
CREATE POLICY conversations_update_admin ON public.conversations
  FOR UPDATE TO authenticated
  USING (public.is_conversation_admin(id) OR created_by = auth.uid());

ALTER TABLE public.conversation_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY conversation_members_select ON public.conversation_members
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_conversation_member(conversation_id));
CREATE POLICY conversation_members_insert ON public.conversation_members
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_conversation_admin(conversation_id)
    OR EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_id AND c.created_by = auth.uid()
    )
  );
CREATE POLICY conversation_members_update_own ON public.conversation_members
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_conversation_admin(conversation_id));
CREATE POLICY conversation_members_delete ON public.conversation_members
  FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR public.is_conversation_admin(conversation_id));

-- Add FK on direct_messages.conversation_id + backfill existing 1:1 conversations
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'direct_messages_conversation_id_fkey') THEN
    ALTER TABLE public.direct_messages
      ADD CONSTRAINT direct_messages_conversation_id_fkey
      FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;
  END IF;
END $$;

WITH pairs AS (
  SELECT DISTINCT
    LEAST(sender_id, receiver_id) AS u1,
    GREATEST(sender_id, receiver_id) AS u2,
    LEAST(sender_id, receiver_id)::text || ':' || GREATEST(sender_id, receiver_id)::text AS dkey,
    max(created_at) AS last_at
  FROM public.direct_messages
  WHERE sender_id IS NOT NULL AND receiver_id IS NOT NULL
  GROUP BY 1, 2, 3
),
ins_conv AS (
  INSERT INTO public.conversations (is_group, direct_key, created_by, last_message_at)
  SELECT false, dkey, u1, last_at FROM pairs
  ON CONFLICT (direct_key) DO NOTHING
  RETURNING id, direct_key
)
INSERT INTO public.conversation_members (conversation_id, user_id, role)
SELECT c.id, p.u1, 'member' FROM pairs p JOIN public.conversations c ON c.direct_key = p.dkey
UNION ALL
SELECT c.id, p.u2, 'member' FROM pairs p JOIN public.conversations c ON c.direct_key = p.dkey
ON CONFLICT (conversation_id, user_id) DO NOTHING;

UPDATE public.direct_messages dm
SET conversation_id = c.id
FROM public.conversations c
WHERE dm.conversation_id IS NULL
  AND dm.sender_id IS NOT NULL
  AND dm.receiver_id IS NOT NULL
  AND c.direct_key = LEAST(dm.sender_id, dm.receiver_id)::text || ':' || GREATEST(dm.sender_id, dm.receiver_id)::text;

-- Auto-link direct_messages to conversations + update last_message preview
CREATE OR REPLACE FUNCTION public.get_or_create_direct_conversation(p_peer_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_dkey text;
  v_conv_id uuid;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_peer_id IS NULL OR p_peer_id = v_me THEN
    RAISE EXCEPTION 'Invalid peer user id';
  END IF;
  IF public.is_blocked_between(v_me, p_peer_id) THEN
    RAISE EXCEPTION 'Conversation unavailable due to block';
  END IF;

  v_dkey := LEAST(v_me, p_peer_id)::text || ':' || GREATEST(v_me, p_peer_id)::text;

  INSERT INTO public.conversations (is_group, direct_key, created_by)
  VALUES (false, v_dkey, v_me)
  ON CONFLICT (direct_key) DO NOTHING
  RETURNING id INTO v_conv_id;

  IF v_conv_id IS NULL THEN
    SELECT id INTO v_conv_id FROM public.conversations WHERE direct_key = v_dkey;
  END IF;

  INSERT INTO public.conversation_members (conversation_id, user_id, role)
  VALUES (v_conv_id, v_me, 'member'), (v_conv_id, p_peer_id, 'member')
  ON CONFLICT (conversation_id, user_id) DO NOTHING;

  RETURN v_conv_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_direct_conversation(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.trg_direct_message_attach_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dkey text;
  v_conv_id uuid;
BEGIN
  IF NEW.conversation_id IS NULL AND NEW.sender_id IS NOT NULL AND NEW.receiver_id IS NOT NULL THEN
    v_dkey := LEAST(NEW.sender_id, NEW.receiver_id)::text || ':' || GREATEST(NEW.sender_id, NEW.receiver_id)::text;
    INSERT INTO public.conversations (is_group, direct_key, created_by)
    VALUES (false, v_dkey, NEW.sender_id)
    ON CONFLICT (direct_key) DO NOTHING;
    SELECT id INTO v_conv_id FROM public.conversations WHERE direct_key = v_dkey;
    INSERT INTO public.conversation_members (conversation_id, user_id, role)
    VALUES (v_conv_id, NEW.sender_id, 'member'), (v_conv_id, NEW.receiver_id, 'member')
    ON CONFLICT (conversation_id, user_id) DO NOTHING;
    NEW.conversation_id := v_conv_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_direct_message_attach_conversation ON public.direct_messages;
CREATE TRIGGER trg_direct_message_attach_conversation
  BEFORE INSERT ON public.direct_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_direct_message_attach_conversation();

CREATE OR REPLACE FUNCTION public.trg_direct_message_update_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.conversation_id IS NOT NULL THEN
    UPDATE public.conversations
    SET last_message_text = COALESCE(NULLIF(BTRIM(NEW.message_text), ''), NEW.attachment_type, NEW.message_type),
        last_message_type = COALESCE(NEW.attachment_type, NEW.message_type, 'text'),
        last_message_at = NEW.created_at,
        last_sender_id = NEW.sender_id,
        updated_at = now()
    WHERE id = NEW.conversation_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_direct_message_update_conversation ON public.direct_messages;
CREATE TRIGGER trg_direct_message_update_conversation
  AFTER INSERT ON public.direct_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_direct_message_update_conversation();

-- Update direct_messages & message_reactions RLS to also support group conversations
DROP POLICY IF EXISTS "Direct Messages Select Policy" ON public.direct_messages;
DROP POLICY IF EXISTS "Direct Messages Update Policy" ON public.direct_messages;
DROP POLICY IF EXISTS "Direct Messages Insert Policy" ON public.direct_messages;
DROP POLICY IF EXISTS direct_messages_insert_unblocked ON public.direct_messages;

CREATE POLICY direct_messages_select_participant ON public.direct_messages
  FOR SELECT TO authenticated
  USING (
    auth.uid() = sender_id
    OR auth.uid() = receiver_id
    OR (conversation_id IS NOT NULL AND public.is_conversation_member(conversation_id))
  );

CREATE POLICY direct_messages_insert_participant ON public.direct_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND (
      (receiver_id IS NOT NULL AND receiver_id <> sender_id AND NOT public.is_blocked_between(sender_id, receiver_id))
      OR
      (receiver_id IS NULL AND conversation_id IS NOT NULL AND public.is_conversation_member(conversation_id))
    )
  );

CREATE POLICY direct_messages_update_participant ON public.direct_messages
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = sender_id
    OR auth.uid() = receiver_id
    OR (conversation_id IS NOT NULL AND public.is_conversation_member(conversation_id))
  );

DROP POLICY IF EXISTS message_reactions_select ON public.message_reactions;
CREATE POLICY message_reactions_select ON public.message_reactions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.direct_messages dm
      WHERE dm.id = message_id
        AND (
          dm.sender_id = auth.uid()
          OR dm.receiver_id = auth.uid()
          OR (dm.conversation_id IS NOT NULL AND public.is_conversation_member(dm.conversation_id))
        )
    )
  );

DROP POLICY IF EXISTS message_reactions_insert ON public.message_reactions;
CREATE POLICY message_reactions_insert ON public.message_reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.direct_messages dm
      WHERE dm.id = message_id
        AND (
          dm.sender_id = auth.uid()
          OR dm.receiver_id = auth.uid()
          OR (dm.conversation_id IS NOT NULL AND public.is_conversation_member(dm.conversation_id))
        )
    )
  );

DROP POLICY IF EXISTS "Stories Select Policy" ON public.user_stories;
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

DROP POLICY IF EXISTS "Allow public read access for discussion_posts" ON public.discussion_posts;
CREATE POLICY discussion_posts_select_visible ON public.discussion_posts
  FOR SELECT TO anon, authenticated
  USING (
    auth.uid() = student_id
    OR (
      deleted_at IS NULL
      AND is_draft = false
      AND (
        (
          COALESCE(visibility, 'public') = 'public'
          AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = student_id AND p.is_private = true)
        )
        OR (
          COALESCE(visibility, 'public') IN ('public', 'followers')
          AND EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = student_id)
        )
      )
    )
  );

DROP POLICY IF EXISTS reels_select ON public.reels;
CREATE POLICY reels_select ON public.reels
  FOR SELECT TO anon, authenticated
  USING (
    auth.uid() = user_id
    OR (
      deleted_at IS NULL
      AND COALESCE(is_published, true) = true
      AND (
        (
          COALESCE(visibility, 'public') = 'public'
          AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = user_id AND p.is_private = true)
        )
        OR (
          COALESCE(visibility, 'public') IN ('public', 'followers')
          AND EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = auth.uid() AND uf.following_id = user_id)
        )
      )
    )
  );

CREATE TABLE IF NOT EXISTS public.message_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.direct_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  delivered_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_message_deliveries UNIQUE (message_id, user_id)
);
ALTER TABLE public.message_deliveries ENABLE ROW LEVEL SECURITY;
CREATE POLICY message_deliveries_select ON public.message_deliveries
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.direct_messages dm WHERE dm.id = message_id AND dm.sender_id = auth.uid())
  );
CREATE POLICY message_deliveries_insert ON public.message_deliveries
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.message_reads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.direct_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  read_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_message_reads UNIQUE (message_id, user_id)
);
ALTER TABLE public.message_reads ENABLE ROW LEVEL SECURITY;
CREATE POLICY message_reads_select ON public.message_reads
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.direct_messages dm WHERE dm.id = message_id AND dm.sender_id = auth.uid())
  );
CREATE POLICY message_reads_insert ON public.message_reads
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.message_deletions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.direct_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  deleted_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_message_deletions UNIQUE (message_id, user_id)
);
ALTER TABLE public.message_deletions ENABLE ROW LEVEL SECURITY;
CREATE POLICY message_deletions_own_all ON public.message_deletions
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.message_edits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.direct_messages(id) ON DELETE CASCADE,
  editor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  previous_text text,
  edited_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.message_edits ENABLE ROW LEVEL SECURITY;
CREATE POLICY message_edits_select ON public.message_edits
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.direct_messages dm
      WHERE dm.id = message_id
        AND (dm.sender_id = auth.uid() OR dm.receiver_id = auth.uid() OR (dm.conversation_id IS NOT NULL AND public.is_conversation_member(dm.conversation_id)))
    )
  );
CREATE POLICY message_edits_insert_sender ON public.message_edits
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = editor_id);

CREATE TABLE IF NOT EXISTS public.conversation_pins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_conversation_pins UNIQUE (conversation_id, user_id)
);
ALTER TABLE public.conversation_pins ENABLE ROW LEVEL SECURITY;
CREATE POLICY conversation_pins_own_all ON public.conversation_pins
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.conversation_mutes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  muted_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_conversation_mutes UNIQUE (conversation_id, user_id)
);
ALTER TABLE public.conversation_mutes ENABLE ROW LEVEL SECURITY;
CREATE POLICY conversation_mutes_own_all ON public.conversation_mutes
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.message_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_message_requests UNIQUE (sender_id, recipient_id)
);
ALTER TABLE public.message_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY message_requests_select ON public.message_requests
  FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
CREATE POLICY message_requests_insert ON public.message_requests
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id AND status = 'pending');
CREATE POLICY message_requests_update_recipient ON public.message_requests
  FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. ADS & MONETIZATION TABLES
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.advertisers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  business_name text NOT NULL,
  website text,
  contact_email text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'suspended')),
  balance numeric(12,2) NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'USD',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.advertisers ENABLE ROW LEVEL SECURITY;
CREATE POLICY advertisers_select_own ON public.advertisers
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_app_admin());
CREATE POLICY advertisers_insert_own ON public.advertisers
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND status = 'pending' AND balance = 0);
CREATE POLICY advertisers_update_own ON public.advertisers
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.ad_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  advertiser_id uuid NOT NULL REFERENCES public.advertisers(id) ON DELETE CASCADE,
  name text NOT NULL,
  objective text NOT NULL DEFAULT 'awareness',
  placement text NOT NULL DEFAULT 'feed' CHECK (placement IN ('feed', 'story', 'reel', 'explore', 'all')),
  status text NOT NULL DEFAULT 'pending_review' CHECK (status IN ('draft', 'pending_review', 'active', 'paused', 'completed', 'rejected')),
  pricing_model text NOT NULL DEFAULT 'CPM' CHECK (pricing_model IN ('CPM', 'CPC', 'CPA')),
  bid_amount numeric(10,4) NOT NULL DEFAULT 2.50,
  daily_budget numeric(12,2) NOT NULL DEFAULT 10.00,
  total_budget numeric(12,2) NOT NULL DEFAULT 100.00,
  spent_amount numeric(12,2) NOT NULL DEFAULT 0.00,
  impressions_count bigint NOT NULL DEFAULT 0,
  clicks_count bigint NOT NULL DEFAULT 0,
  conversions_count bigint NOT NULL DEFAULT 0,
  starts_at timestamptz NOT NULL DEFAULT now(),
  ends_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ad_campaigns_active_placement ON public.ad_campaigns (status, placement, starts_at) WHERE status = 'active';
ALTER TABLE public.ad_campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY ad_campaigns_select ON public.ad_campaigns
  FOR SELECT TO authenticated
  USING (
    status = 'active'
    OR EXISTS (SELECT 1 FROM public.advertisers a WHERE a.id = advertiser_id AND a.user_id = auth.uid())
    OR public.is_app_admin()
  );
CREATE POLICY ad_campaigns_manage_owner ON public.ad_campaigns
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.advertisers a WHERE a.id = advertiser_id AND a.user_id = auth.uid()))
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.advertisers a WHERE a.id = advertiser_id AND a.user_id = auth.uid())
    AND status IN ('draft', 'pending_review', 'paused')
  );

CREATE TABLE IF NOT EXISTS public.ad_creatives (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  title text NOT NULL,
  body text NOT NULL,
  media_url text,
  media_type text NOT NULL DEFAULT 'image',
  cta_label text NOT NULL DEFAULT 'Learn More',
  destination_url text NOT NULL,
  status text NOT NULL DEFAULT 'pending_review',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ad_creatives ENABLE ROW LEVEL SECURITY;
CREATE POLICY ad_creatives_select ON public.ad_creatives
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND (c.status = 'active' OR a.user_id = auth.uid())
    )
    OR public.is_app_admin()
  );
CREATE POLICY ad_creatives_manage_owner ON public.ad_creatives
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
  );

CREATE TABLE IF NOT EXISTS public.ad_targeting (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL UNIQUE REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  countries text[] NOT NULL DEFAULT '{}',
  languages text[] NOT NULL DEFAULT '{}',
  interests text[] NOT NULL DEFAULT '{}',
  min_age integer NOT NULL DEFAULT 13,
  max_age integer NOT NULL DEFAULT 99,
  gender text NOT NULL DEFAULT 'all',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ad_targeting ENABLE ROW LEVEL SECURITY;
CREATE POLICY ad_targeting_manage_owner ON public.ad_targeting
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
  );

CREATE TABLE IF NOT EXISTS public.ad_impressions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  creative_id uuid REFERENCES public.ad_creatives(id) ON DELETE SET NULL,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  placement text NOT NULL,
  idempotency_key text UNIQUE,
  cost_charged numeric(10,6) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ad_impressions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ad_impressions_select_owner ON public.ad_impressions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
    OR public.is_app_admin()
  );

CREATE TABLE IF NOT EXISTS public.ad_clicks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  creative_id uuid REFERENCES public.ad_creatives(id) ON DELETE SET NULL,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  placement text NOT NULL,
  idempotency_key text UNIQUE,
  cost_charged numeric(10,6) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ad_clicks ENABLE ROW LEVEL SECURITY;
CREATE POLICY ad_clicks_select_owner ON public.ad_clicks
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
    OR public.is_app_admin()
  );

CREATE TABLE IF NOT EXISTS public.ad_conversions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  event_name text NOT NULL,
  value numeric(12,2) NOT NULL DEFAULT 0,
  idempotency_key text UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ad_conversions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ad_conversions_select_owner ON public.ad_conversions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ad_campaigns c
      JOIN public.advertisers a ON a.id = c.advertiser_id
      WHERE c.id = campaign_id AND a.user_id = auth.uid()
    )
    OR public.is_app_admin()
  );

CREATE TABLE IF NOT EXISTS public.ad_frequency_caps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  impressions_today integer NOT NULL DEFAULT 0,
  last_shown_at timestamptz NOT NULL DEFAULT now(),
  window_date date NOT NULL DEFAULT CURRENT_DATE,
  CONSTRAINT uq_ad_frequency_caps UNIQUE (campaign_id, user_id, window_date)
);
ALTER TABLE public.ad_frequency_caps ENABLE ROW LEVEL SECURITY;
CREATE POLICY ad_frequency_caps_select_own ON public.ad_frequency_caps
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.ad_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  advertiser_id uuid NOT NULL REFERENCES public.advertisers(id) ON DELETE CASCADE,
  campaign_id uuid REFERENCES public.ad_campaigns(id) ON DELETE SET NULL,
  invoice_number text NOT NULL UNIQUE,
  amount numeric(12,2) NOT NULL,
  currency text NOT NULL DEFAULT 'USD',
  status text NOT NULL DEFAULT 'issued',
  period_start timestamptz,
  period_end timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ad_invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY ad_invoices_select_owner ON public.ad_invoices
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.advertisers a WHERE a.id = advertiser_id AND a.user_id = auth.uid())
    OR public.is_app_admin()
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. LIVE STREAMING FOUNDATION TABLES
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.live_streams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title text NOT NULL,
  category text NOT NULL DEFAULT 'General',
  thumbnail_url text,
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'live', 'ended')),
  viewer_count integer NOT NULL DEFAULT 0,
  peak_viewer_count integer NOT NULL DEFAULT 0,
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_live_streams_status ON public.live_streams (status, created_at DESC);
ALTER TABLE public.live_streams ENABLE ROW LEVEL SECURITY;
CREATE POLICY live_streams_select_all ON public.live_streams FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY live_streams_manage_host ON public.live_streams FOR ALL TO authenticated USING (auth.uid() = host_id) WITH CHECK (auth.uid() = host_id);

CREATE TABLE IF NOT EXISTS public.live_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id uuid NOT NULL REFERENCES public.live_streams(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  comment_text text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_live_comments_stream ON public.live_comments (stream_id, created_at DESC);
ALTER TABLE public.live_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY live_comments_select ON public.live_comments FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY live_comments_insert ON public.live_comments FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.live_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id uuid NOT NULL REFERENCES public.live_streams(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji text NOT NULL DEFAULT '❤️',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.live_reactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY live_reactions_select ON public.live_reactions FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY live_reactions_insert ON public.live_reactions FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.live_viewers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stream_id uuid NOT NULL REFERENCES public.live_streams(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at timestamptz NOT NULL DEFAULT now(),
  left_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT uq_live_viewers UNIQUE (stream_id, user_id)
);
ALTER TABLE public.live_viewers ENABLE ROW LEVEL SECURITY;
CREATE POLICY live_viewers_select ON public.live_viewers FOR SELECT TO authenticated USING (true);
CREATE POLICY live_viewers_manage_own ON public.live_viewers FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. HIGH-VALUE COMPOSITE, PARTIAL & SEARCH INDEXES
-- ═══════════════════════════════════════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_discussion_posts_feed_cursor
  ON public.discussion_posts (created_at DESC, id DESC)
  WHERE deleted_at IS NULL AND is_draft = false;

CREATE INDEX IF NOT EXISTS idx_discussion_posts_author_created
  ON public.discussion_posts (student_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_discussion_posts_search_gin
  ON public.discussion_posts
  USING gin (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(content, '')));

CREATE INDEX IF NOT EXISTS idx_discussion_likes_post ON public.discussion_likes (post_id);
CREATE INDEX IF NOT EXISTS idx_discussion_bookmarks_user_created ON public.discussion_bookmarks (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_post_reposts_post ON public.post_reposts (post_id);

CREATE INDEX IF NOT EXISTS idx_reels_published_cursor
  ON public.reels (created_at DESC, id DESC)
  WHERE deleted_at IS NULL AND is_published = true;

CREATE INDEX IF NOT EXISTS idx_reels_author_created
  ON public.reels (user_id, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_direct_messages_conv_created
  ON public.direct_messages (conversation_id, created_at DESC)
  WHERE conversation_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_search_gin
  ON public.profiles
  USING gin (to_tsvector('simple', coalesce(username, '') || ' ' || coalesce(first_name, '') || ' ' || coalesce(last_name, '')));

CREATE INDEX IF NOT EXISTS idx_profiles_referral_count_desc
  ON public.profiles (referral_count DESC, created_at ASC);
