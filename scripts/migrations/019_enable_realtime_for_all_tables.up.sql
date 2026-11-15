-- 019_enable_realtime_for_all_tables.up.sql
-- Zero-to-One Realtime Enablement for ALL Supabase Database Tables:
-- 1. Creates/ensures supabase_realtime publication
-- 2. Sets REPLICA IDENTITY FULL on every public table so full row payloads (NEW & OLD) are broadcast
-- 3. Dynamically enumerates and adds ALL public tables to supabase_realtime
-- 4. Explicitly verifies and adds every core table (posts, likes, comments, calls, messages, notifications, follows, stories, live, ads, profiles)
-- 5. Ensures transparent SELECT RLS policies exist so Supabase Realtime WebSocket engine delivers events to authenticated clients

-- 1. Ensure supabase_realtime publication exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;
END $$;

-- 2. Dynamically add ALL existing tables in public schema to supabase_realtime
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN (
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
  ) LOOP
    BEGIN
      -- Set REPLICA IDENTITY FULL so all columns (including OLD records on UPDATE/DELETE) are sent via Realtime
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL;', r.tablename);
      -- Add table to supabase_realtime publication
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', r.tablename);
    EXCEPTION
      WHEN duplicate_object THEN
        NULL;
      WHEN OTHERS THEN
        RAISE NOTICE 'Notice: table % in publication: %', r.tablename, SQLERRM;
    END;
  END LOOP;
END $$;

-- 3. Explicit Guarantee & Idempotent Addition of Core Interactive Tables
DO $$
DECLARE
  v_core_tables text[] := ARRAY[
    'profiles',
    'discussion_posts',
    'discussion_comments',
    'discussion_likes',
    'discussion_bookmarks',
    'post_media',
    'post_reports',
    'post_reposts',
    'post_views',
    'post_hashtags',
    'hashtags',
    'trending_topics',
    'user_follows',
    'follow_requests',
    'user_notifications',
    'notification_deliveries',
    'notification_preferences',
    'conversations',
    'conversation_members',
    'conversation_pins',
    'conversation_mutes',
    'direct_messages',
    'message_reads',
    'message_reactions',
    'message_deliveries',
    'message_edits',
    'message_deletions',
    'message_requests',
    'call_sessions',
    'call_participants',
    'user_stories',
    'story_views',
    'story_likes',
    'story_reactions',
    'story_replies',
    'story_mutes',
    'live_streams',
    'live_comments',
    'live_reactions',
    'live_viewers',
    'reels',
    'reel_likes',
    'reel_comments',
    'reel_views',
    'reel_bookmarks',
    'ad_campaigns',
    'ad_creatives',
    'ad_targeting',
    'ad_impressions',
    'ad_clicks',
    'ad_conversions',
    'ad_invoices',
    'advertisers',
    'comment_likes',
    'comment_pins',
    'user_blocks',
    'user_mutes',
    'user_notes',
    'user_links',
    'user_devices',
    'user_settings',
    'user_preferences',
    'user_privacy_settings',
    'user_security_logs',
    'user_sessions',
    'close_friends',
    'hidden_posts',
    'search_history',
    'subscriptions',
    'referrals'
  ];
  v_tbl text;
BEGIN
  FOREACH v_tbl IN ARRAY v_core_tables LOOP
    IF EXISTS (
      SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = v_tbl
    ) THEN
      BEGIN
        EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL;', v_tbl);
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I;', v_tbl);
      EXCEPTION
        WHEN duplicate_object THEN
          NULL;
        WHEN OTHERS THEN
          RAISE NOTICE 'Table % already in publication or notice: %', v_tbl, SQLERRM;
      END;
    END IF;
  END LOOP;
END $$;

-- 4. Ensure SELECT RLS policies exist on interactive social tables so Realtime events stream seamlessly
-- Notifications
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'user_notifications') THEN
    DROP POLICY IF EXISTS user_notifications_realtime_select ON public.user_notifications;
    CREATE POLICY user_notifications_realtime_select
      ON public.user_notifications
      FOR SELECT
      TO authenticated
      USING (user_id = auth.uid() OR public.is_app_admin());
  END IF;
END $$;

-- Discussion Likes (Public read for real-time like counter synchronization)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'discussion_likes') THEN
    DROP POLICY IF EXISTS discussion_likes_realtime_select ON public.discussion_likes;
    CREATE POLICY discussion_likes_realtime_select
      ON public.discussion_likes
      FOR SELECT
      TO authenticated, anon
      USING (true);
  END IF;
END $$;

-- Discussion Comments (Public read for active posts)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'discussion_comments') THEN
    DROP POLICY IF EXISTS discussion_comments_realtime_select ON public.discussion_comments;
    CREATE POLICY discussion_comments_realtime_select
      ON public.discussion_comments
      FOR SELECT
      TO authenticated, anon
      USING (deleted_at IS NULL);
  END IF;
END $$;

-- User Follows (Public read for live follower/following counts)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'user_follows') THEN
    DROP POLICY IF EXISTS user_follows_realtime_select ON public.user_follows;
    CREATE POLICY user_follows_realtime_select
      ON public.user_follows
      FOR SELECT
      TO authenticated, anon
      USING (true);
  END IF;
END $$;

-- Call Sessions (Caller, callee or admin)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'call_sessions') THEN
    DROP POLICY IF EXISTS call_sessions_realtime_select ON public.call_sessions;
    CREATE POLICY call_sessions_realtime_select
      ON public.call_sessions
      FOR SELECT
      TO authenticated
      USING (
        caller_id = auth.uid()
        OR callee_id = auth.uid()
        OR is_group = true
        OR public.is_app_admin()
      );
  END IF;
END $$;

-- Call Participants
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'call_participants') THEN
    DROP POLICY IF EXISTS call_participants_realtime_select ON public.call_participants;
    CREATE POLICY call_participants_realtime_select
      ON public.call_participants
      FOR SELECT
      TO authenticated
      USING (
        user_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.call_sessions cs
          WHERE cs.id = call_session_id
            AND (cs.caller_id = auth.uid() OR cs.callee_id = auth.uid() OR cs.is_group = true)
        )
        OR public.is_app_admin()
      );
  END IF;
END $$;

-- Live Streams
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'live_streams') THEN
    DROP POLICY IF EXISTS live_streams_realtime_select ON public.live_streams;
    CREATE POLICY live_streams_realtime_select
      ON public.live_streams
      FOR SELECT
      TO authenticated, anon
      USING (true);
  END IF;
END $$;

