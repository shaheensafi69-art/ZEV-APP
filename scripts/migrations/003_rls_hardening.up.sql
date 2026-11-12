-- 003_rls_hardening.up.sql
-- 1. Add public.is_blocked_between helper.
-- 2. Replace all overly permissive USING(true)/WITH CHECK(true) write policies with
--    strict authenticated owner + block-aware policies.
-- 3. Protect privileged columns on public.profiles from client self-escalation.
-- 4. Add missing RLS policies on the 6 RLS-enabled tables that had 0 policies.

CREATE OR REPLACE FUNCTION public.is_blocked_between(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_blocks b
    WHERE (b.blocker_id = p_a AND b.blocked_id = p_b)
       OR (b.blocker_id = p_b AND b.blocked_id = p_a)
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked_between(uuid, uuid) TO authenticated;

-- 1. Harden public.profiles policies + column protection
DROP POLICY IF EXISTS "Allow authenticated users to view profiles" ON public.profiles;
DROP POLICY IF EXISTS "Allow public read access for profiles" ON public.profiles;
DROP POLICY IF EXISTS "Public Read Access for Profiles" ON public.profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
DROP POLICY IF EXISTS profiles_select ON public.profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS "Allow admin full update access" ON public.profiles;

CREATE POLICY profiles_select_all ON public.profiles
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY profiles_insert_own ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = id
    AND COALESCE(is_verified, false) = false
    AND COALESCE(lifetime_blue_eligible, false) = false
    AND COALESCE(referral_count, 0) = 0
    AND referred_by IS NULL
    AND COALESCE(is_restricted, false) = false
    AND COALESCE(warning_count, 0) = 0
  );

CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY profiles_update_admin ON public.profiles
  FOR UPDATE TO authenticated
  USING (public.is_app_admin())
  WITH CHECK (public.is_app_admin());

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
     OR NEW.last_warning_reason IS DISTINCT FROM OLD.last_warning_reason THEN
    RAISE EXCEPTION 'Insufficient privileges to modify protected profile attributes'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_privileged_columns ON public.profiles;
CREATE TRIGGER trg_protect_profile_privileged_columns
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_profile_privileged_columns();

-- 2. Harden reels & reel_* tables
DROP POLICY IF EXISTS "Reels Select Policy" ON public.reels;
DROP POLICY IF EXISTS "Reels Insert Policy" ON public.reels;
DROP POLICY IF EXISTS "Reels Update Policy" ON public.reels;
DROP POLICY IF EXISTS "Reels Delete Policy" ON public.reels;

CREATE POLICY reels_select ON public.reels
  FOR SELECT TO anon, authenticated
  USING (COALESCE(is_published, true) = true OR auth.uid() = user_id);

CREATE POLICY reels_insert_own ON public.reels
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY reels_update_own ON public.reels
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY reels_delete_own ON public.reels
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Reel Likes Select Policy" ON public.reel_likes;
DROP POLICY IF EXISTS "Reel Likes Insert Policy" ON public.reel_likes;
DROP POLICY IF EXISTS "Reel Likes Delete Policy" ON public.reel_likes;
DROP POLICY IF EXISTS "Reel Likes Manage Policy" ON public.reel_likes;

CREATE POLICY reel_likes_select ON public.reel_likes
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY reel_likes_insert_own ON public.reel_likes
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY reel_likes_delete_own ON public.reel_likes
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Reel Comments Select Policy" ON public.reel_comments;
DROP POLICY IF EXISTS "Reel Comments Insert Policy" ON public.reel_comments;
DROP POLICY IF EXISTS "Reel Comments Update Policy" ON public.reel_comments;
DROP POLICY IF EXISTS "Reel Comments Delete Policy" ON public.reel_comments;
DROP POLICY IF EXISTS "Reel Comments Manage Policy" ON public.reel_comments;

CREATE POLICY reel_comments_select ON public.reel_comments
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY reel_comments_insert_own ON public.reel_comments
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY reel_comments_update_own ON public.reel_comments
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY reel_comments_delete_own_or_owner ON public.reel_comments
  FOR DELETE TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (SELECT 1 FROM public.reels r WHERE r.id = reel_id AND r.user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Reel Views Select Policy" ON public.reel_views;
DROP POLICY IF EXISTS "Reel Views Insert Policy" ON public.reel_views;

CREATE POLICY reel_views_select ON public.reel_views
  FOR SELECT TO anon, authenticated
  USING (true);

CREATE POLICY reel_views_insert_own ON public.reel_views
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = viewer_id);

CREATE POLICY reel_views_update_own ON public.reel_views
  FOR UPDATE TO authenticated
  USING (auth.uid() = viewer_id)
  WITH CHECK (auth.uid() = viewer_id);

-- 3. Harden discussion_posts, discussion_comments, hashtags link tables
DROP POLICY IF EXISTS discussion_posts_update_own ON public.discussion_posts;
CREATE POLICY discussion_posts_update_own ON public.discussion_posts
  FOR UPDATE TO authenticated
  USING (auth.uid() = student_id)
  WITH CHECK (auth.uid() = student_id);

DROP POLICY IF EXISTS discussion_posts_delete_own ON public.discussion_posts;
CREATE POLICY discussion_posts_delete_own ON public.discussion_posts
  FOR DELETE TO authenticated
  USING (auth.uid() = student_id);

DROP POLICY IF EXISTS discussion_comments_delete_post_owner ON public.discussion_comments;
CREATE POLICY discussion_comments_delete_post_owner ON public.discussion_comments
  FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = post_id AND p.student_id = auth.uid())
  );

DROP POLICY IF EXISTS "Authenticated users can link post hashtags" ON public.post_hashtags;
CREATE POLICY post_hashtags_insert_owner ON public.post_hashtags
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = post_id AND p.student_id = auth.uid())
  );
CREATE POLICY post_hashtags_delete_owner ON public.post_hashtags
  FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.discussion_posts p WHERE p.id = post_id AND p.student_id = auth.uid())
  );

DROP POLICY IF EXISTS "Authenticated users can link reel hashtags" ON public.reel_hashtags;
CREATE POLICY reel_hashtags_insert_owner ON public.reel_hashtags
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.reels r WHERE r.id = reel_id AND r.user_id = auth.uid())
  );
CREATE POLICY reel_hashtags_delete_owner ON public.reel_hashtags
  FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.reels r WHERE r.id = reel_id AND r.user_id = auth.uid())
  );

-- Restrict hashtag creation to authenticated role cleanly
DROP POLICY IF EXISTS "Authenticated users can insert hashtags" ON public.hashtags;
DROP POLICY IF EXISTS "Authenticated users can update hashtags" ON public.hashtags;
CREATE POLICY hashtags_insert_auth ON public.hashtags
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- 4. Harden direct_messages, user_follows, student_friends, user_notifications
DROP POLICY IF EXISTS "Direct Messages Insert Policy" ON public.direct_messages;
CREATE POLICY direct_messages_insert_unblocked ON public.direct_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND (
      receiver_id IS NULL
      OR (receiver_id <> sender_id AND NOT public.is_blocked_between(sender_id, receiver_id))
    )
  );

DROP POLICY IF EXISTS "Users can follow other users" ON public.user_follows;
DROP POLICY IF EXISTS "Users can unfollow" ON public.user_follows;

CREATE POLICY user_follows_insert_unblocked ON public.user_follows
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = follower_id
    AND follower_id <> following_id
    AND NOT public.is_blocked_between(follower_id, following_id)
  );

CREATE POLICY user_follows_delete_participant ON public.user_follows
  FOR DELETE TO authenticated
  USING (auth.uid() = follower_id OR auth.uid() = following_id);

DROP POLICY IF EXISTS "Enable read access for all users" ON public.student_friends;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON public.student_friends;
DROP POLICY IF EXISTS "Enable update for involved users" ON public.student_friends;
DROP POLICY IF EXISTS "Enable delete for involved users" ON public.student_friends;

DROP POLICY IF EXISTS "Allow authenticated users to insert notifications" ON public.user_notifications;
CREATE POLICY user_notifications_insert_sender ON public.user_notifications
  FOR INSERT TO authenticated
  WITH CHECK (
    (sender_id = auth.uid() OR (user_id = auth.uid() AND sender_id IS NULL))
    AND NOT public.is_blocked_between(auth.uid(), user_id)
  );

-- 5. Add explicit policies for the 6 RLS-enabled tables that had 0 policies
DROP POLICY IF EXISTS admin_audit_logs_select_admin ON public.admin_audit_logs;
CREATE POLICY admin_audit_logs_select_admin ON public.admin_audit_logs
  FOR SELECT TO authenticated
  USING (public.is_app_admin());

DROP POLICY IF EXISTS message_reactions_select ON public.message_reactions;
CREATE POLICY message_reactions_select ON public.message_reactions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.direct_messages dm
      WHERE dm.id = message_id
        AND (dm.sender_id = auth.uid() OR dm.receiver_id = auth.uid())
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
        AND (dm.sender_id = auth.uid() OR dm.receiver_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS message_reactions_delete ON public.message_reactions;
CREATE POLICY message_reactions_delete ON public.message_reactions
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS referrals_select_own ON public.referrals;
CREATE POLICY referrals_select_own ON public.referrals
  FOR SELECT TO authenticated
  USING (auth.uid() = referrer_id OR auth.uid() = referee_id);

DROP POLICY IF EXISTS story_views_select ON public.story_views;
CREATE POLICY story_views_select ON public.story_views
  FOR SELECT TO authenticated
  USING (
    auth.uid() = viewer_id
    OR EXISTS (SELECT 1 FROM public.user_stories s WHERE s.id = story_id AND s.user_id = auth.uid())
  );

DROP POLICY IF EXISTS story_views_insert_own ON public.story_views;
CREATE POLICY story_views_insert_own ON public.story_views
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = viewer_id
    AND EXISTS (
      SELECT 1 FROM public.user_stories s
      WHERE s.id = story_id
        AND NOT public.is_blocked_between(auth.uid(), s.user_id)
    )
  );

DROP POLICY IF EXISTS subscriptions_select_own ON public.subscriptions;
CREATE POLICY subscriptions_select_own ON public.subscriptions
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS subscriptions_insert_pending_own ON public.subscriptions;
CREATE POLICY subscriptions_insert_pending_own ON public.subscriptions
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND status = 'pending'
    AND COALESCE(is_active, false) = false
  );

DROP POLICY IF EXISTS user_restrictions_select_own ON public.user_restrictions;
CREATE POLICY user_restrictions_select_own ON public.user_restrictions
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

