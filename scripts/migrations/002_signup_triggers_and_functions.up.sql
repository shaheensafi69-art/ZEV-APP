-- 002_signup_triggers_and_functions.up.sql
-- 1. Align username normalization/generation with ^[a-z0-9_.]{3,30}$ (preserving dots).
-- 2. Add is_username_available RPC.
-- 3. Backfill all active auth.users missing a public.profiles row (deduplicating usernames).
-- 4. Install on_auth_user_created trigger on auth.users.
-- 5. Fix broken notify_on_reel_comment, create_direct_message_notification,
--    get_admin_dashboard_stats, sync_profile_verification, and expire_stale_subscriptions.

CREATE OR REPLACE FUNCTION public.generate_unique_username(
  p_first_name text,
  p_last_name text,
  p_email text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw text;
  v_base text;
  v_candidate text;
  v_counter int := 0;
  v_suffix text;
BEGIN
  v_raw := lower(
    coalesce(btrim(p_first_name), '') || '_' || coalesce(btrim(p_last_name), '')
  );
  v_base := regexp_replace(v_raw, '[^a-z0-9_.]', '', 'g');
  v_base := regexp_replace(v_base, '[_]{2,}', '_', 'g');
  v_base := regexp_replace(v_base, '[.]{2,}', '.', 'g');
  v_base := regexp_replace(v_base, '^[_.]+|[_.]+$', '', 'g');

  IF length(v_base) < 3 THEN
    v_base := lower(
      regexp_replace(split_part(coalesce(p_email, 'zev_user'), '@', 1), '[^a-z0-9_.]', '', 'g')
    );
    v_base := regexp_replace(v_base, '[_]{2,}', '_', 'g');
    v_base := regexp_replace(v_base, '[.]{2,}', '.', 'g');
    v_base := regexp_replace(v_base, '^[_.]+|[_.]+$', '', 'g');
  END IF;

  IF length(v_base) < 3 THEN
    v_base := 'zev_user';
  END IF;

  v_base := left(v_base, 24);
  v_candidate := v_base;

  WHILE EXISTS (
    SELECT 1 FROM public.profiles WHERE lower(username) = lower(v_candidate)
  ) LOOP
    v_counter := v_counter + 1;
    v_suffix := '_' || v_counter::text;
    v_candidate := left(v_base, 30 - length(v_suffix)) || v_suffix;
  END LOOP;

  RETURN v_candidate;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_assign_auto_username()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.username IS NULL OR btrim(NEW.username) = '' THEN
    NEW.username := public.generate_unique_username(NEW.first_name, NEW.last_name, NEW.email);
  ELSE
    NEW.username := lower(
      regexp_replace(btrim(replace(NEW.username, '@', '')), '[^a-z0-9_.]', '', 'g')
    );
  END IF;
  IF (NEW.referral_code IS NULL OR btrim(NEW.referral_code) = '')
     AND NEW.username IS NOT NULL AND NEW.username <> '' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles
      WHERE referral_code = NEW.username AND id <> NEW.id
    ) THEN
      NEW.referral_code := NEW.username;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_username_available(p_username text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean text;
BEGIN
  v_clean := lower(btrim(replace(coalesce(p_username, ''), '@', '')));
  IF NOT (v_clean ~ '^[a-z0-9_.]{3,30}$') THEN
    RETURN false;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE lower(username) = v_clean
      AND id IS DISTINCT FROM auth.uid()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_username_available(text) TO anon, authenticated;

-- Backfill all existing active auth.users lacking a profile
DO $$
DECLARE
  rec record;
  v_fn text;
  v_ln text;
  v_full text;
  v_req_un text;
  v_un text;
  v_ref_code text;
  v_email text;
  v_missing int;
BEGIN
  FOR rec IN
    SELECT u.id, u.email, u.raw_user_meta_data, u.created_at
    FROM auth.users u
    WHERE u.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
    ORDER BY u.created_at ASC
  LOOP
    v_full := coalesce(
      nullif(btrim(rec.raw_user_meta_data->>'full_name'), ''),
      nullif(btrim(rec.raw_user_meta_data->>'name'), ''),
      ''
    );
    v_fn := coalesce(
      nullif(btrim(rec.raw_user_meta_data->>'first_name'), ''),
      nullif(split_part(v_full, ' ', 1), ''),
      nullif(split_part(coalesce(rec.email, ''), '@', 1), ''),
      'ZEV'
    );
    v_ln := coalesce(
      nullif(btrim(rec.raw_user_meta_data->>'last_name'), ''),
      nullif(btrim(regexp_replace(v_full, '^\S+\s*', '')), ''),
      'User'
    );
    v_email := coalesce(nullif(btrim(rec.email), ''), rec.id::text || '@user.zevapp.com');

    v_req_un := lower(
      regexp_replace(btrim(replace(coalesce(rec.raw_user_meta_data->>'username', ''), '@', '')), '[^a-z0-9_.]', '', 'g')
    );

    IF v_req_un ~ '^[a-z0-9_.]{3,30}$'
       AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = v_req_un) THEN
      v_un := v_req_un;
    ELSE
      v_un := public.generate_unique_username(v_fn, v_ln, v_email);
    END IF;

    v_ref_code := v_un;
    IF EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = v_ref_code) THEN
      v_ref_code := left(v_un, 24) || '_' || left(replace(rec.id::text, '-', ''), 4);
    END IF;

    INSERT INTO public.profiles (
      id, first_name, last_name, email, username, referral_code, avatar_url, created_at, updated_at
    ) VALUES (
      rec.id,
      v_fn,
      v_ln,
      v_email,
      v_un,
      v_ref_code,
      nullif(btrim(rec.raw_user_meta_data->>'avatar_url'), ''),
      coalesce(rec.created_at, now()),
      now()
    )
    ON CONFLICT (id) DO NOTHING;
  END LOOP;

  SELECT count(*) INTO v_missing
  FROM auth.users u
  WHERE u.deleted_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);

  IF v_missing > 0 THEN
    RAISE EXCEPTION 'Backfill failed: % auth.users still missing profile', v_missing;
  END IF;
END $$;

-- Re-point discussion_posts.student_id FK to public.profiles(id) for PostgREST joins
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'discussion_posts_student_id_fkey') THEN
    ALTER TABLE public.discussion_posts DROP CONSTRAINT discussion_posts_student_id_fkey;
  END IF;
  ALTER TABLE public.discussion_posts
    ADD CONSTRAINT discussion_posts_student_id_fkey
    FOREIGN KEY (student_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
END $$;

-- Auth signup trigger function
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_full text;
  v_fn text;
  v_ln text;
  v_email text;
  v_req_un text;
  v_un text;
  v_ref_code text;
BEGIN
  v_full := coalesce(
    nullif(btrim(NEW.raw_user_meta_data->>'full_name'), ''),
    nullif(btrim(NEW.raw_user_meta_data->>'name'), ''),
    ''
  );
  v_fn := coalesce(
    nullif(btrim(NEW.raw_user_meta_data->>'first_name'), ''),
    nullif(split_part(v_full, ' ', 1), ''),
    nullif(split_part(coalesce(NEW.email, ''), '@', 1), ''),
    'ZEV'
  );
  v_ln := coalesce(
    nullif(btrim(NEW.raw_user_meta_data->>'last_name'), ''),
    nullif(btrim(regexp_replace(v_full, '^\S+\s*', '')), ''),
    'User'
  );
  v_email := coalesce(nullif(btrim(NEW.email), ''), NEW.id::text || '@user.zevapp.com');

  v_req_un := lower(
    regexp_replace(btrim(replace(coalesce(NEW.raw_user_meta_data->>'username', ''), '@', '')), '[^a-z0-9_.]', '', 'g')
  );

  IF v_req_un ~ '^[a-z0-9_.]{3,30}$'
     AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = v_req_un) THEN
    v_un := v_req_un;
  ELSE
    v_un := public.generate_unique_username(v_fn, v_ln, v_email);
  END IF;

  v_ref_code := v_un;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = v_ref_code) THEN
    v_ref_code := left(v_un, 24) || '_' || left(replace(NEW.id::text, '-', ''), 4);
  END IF;

  INSERT INTO public.profiles (
    id, first_name, last_name, email, username, referral_code, avatar_url, created_at, updated_at
  ) VALUES (
    NEW.id,
    v_fn,
    v_ln,
    v_email,
    v_un,
    v_ref_code,
    nullif(btrim(NEW.raw_user_meta_data->>'avatar_url'), ''),
    coalesce(NEW.created_at, now()),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

-- Fix notify_on_reel_comment (previously referenced non-existent NEW.comment!)
CREATE OR REPLACE FUNCTION public.notify_on_reel_comment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_id uuid;
  v_snippet text;
BEGIN
  SELECT user_id INTO v_owner_id FROM public.reels WHERE id = NEW.reel_id;

  IF v_owner_id IS NOT NULL
     AND v_owner_id <> NEW.user_id
     AND NOT EXISTS (
       SELECT 1 FROM public.user_blocks b
       WHERE (b.blocker_id = v_owner_id AND b.blocked_id = NEW.user_id)
          OR (b.blocker_id = NEW.user_id AND b.blocked_id = v_owner_id)
     ) THEN
    v_snippet := left(coalesce(NEW.comment_text, ''), 80);

    INSERT INTO public.user_notifications (
      user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
    ) VALUES (
      v_owner_id,
      NEW.user_id,
      'New Reel Comment',
      CASE WHEN v_snippet <> '' THEN 'commented: "' || v_snippet || '"' ELSE 'commented on your reel.' END,
      'reel_comment',
      NEW.reel_id::text,
      false,
      'zev',
      now()
    );
  END IF;
  RETURN NEW;
END;
$$;

-- Update tr_fn_direct_message_set_delivery to support group chats safely when receiver_id IS NULL
CREATE OR REPLACE FUNCTION public.tr_fn_direct_message_set_delivery()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  receiver_online boolean;
  receiver_last_seen timestamptz;
BEGIN
  IF NEW.receiver_id IS NULL THEN
    NEW.is_delivered := true;
    NEW.delivered_at := COALESCE(NEW.delivered_at, now());
    NEW.is_read := false;
    NEW.read_at := NULL;
    RETURN NEW;
  END IF;

  SELECT is_online, COALESCE(last_seen_at, last_seen)
  INTO receiver_online, receiver_last_seen
  FROM public.profiles WHERE id = NEW.receiver_id;

  IF receiver_online IS TRUE AND receiver_last_seen > (now() - interval '3 minutes') THEN
    NEW.is_delivered := true;
    IF NEW.delivered_at IS NULL THEN
      NEW.delivered_at := now();
    END IF;
  ELSE
    NEW.is_delivered := false;
    NEW.delivered_at := NULL;
  END IF;

  NEW.is_read := false;
  NEW.read_at := NULL;

  RETURN NEW;
END;
$$;

-- Rewrite create_direct_message_notification in English, block-aware, and ZEV-consistent
CREATE OR REPLACE FUNCTION public.create_direct_message_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_preview text;
BEGIN
  IF NEW.receiver_id IS NULL OR NEW.receiver_id = NEW.sender_id THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_blocks b
    WHERE (b.blocker_id = NEW.receiver_id AND b.blocked_id = NEW.sender_id)
       OR (b.blocker_id = NEW.sender_id AND b.blocked_id = NEW.receiver_id)
  ) THEN
    RETURN NEW;
  END IF;

  v_preview := left(
    coalesce(
      nullif(btrim(NEW.message_text), ''),
      CASE WHEN NEW.attachment_url IS NOT NULL THEN 'Sent an attachment' ELSE 'Sent you a message' END
    ),
    120
  );

  INSERT INTO public.user_notifications (
    user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
  ) VALUES (
    NEW.receiver_id,
    NEW.sender_id,
    'New Message',
    v_preview,
    'direct_message',
    '/chat/' || NEW.sender_id::text,
    false,
    'zev',
    now()
  );

  RETURN NEW;
END;
$$;

-- Update legacy unused notify_on_direct_message to clean English as well
CREATE OR REPLACE FUNCTION public.notify_on_direct_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sender_name text;
BEGIN
  IF NEW.receiver_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT COALESCE(NULLIF(BTRIM(first_name || ' ' || last_name), ''), username, 'A ZEV user')
  INTO sender_name
  FROM public.profiles WHERE id = NEW.sender_id;

  INSERT INTO public.user_notifications (user_id, sender_id, title, message, notification_type, app_source)
  VALUES (
    NEW.receiver_id,
    NEW.sender_id,
    'New message from ' || sender_name,
    LEFT(COALESCE(NEW.message_text, 'Sent an attachment'), 100),
    'chat',
    'zev'
  );
  RETURN NEW;
END;
$$;

-- Fix get_admin_dashboard_stats to query real ZEV tables
CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_users int;
  v_verified int;
  v_restricted int;
  v_posts int;
  v_reels int;
  v_tickets int;
  v_reports int;
  v_active_subs int;
BEGIN
  SELECT count(*) INTO v_users FROM public.profiles;
  SELECT count(*) INTO v_verified FROM public.profiles WHERE is_verified = true;
  SELECT count(*) INTO v_restricted FROM public.profiles WHERE is_restricted = true;
  SELECT count(*) INTO v_posts FROM public.discussion_posts;
  SELECT count(*) INTO v_reels FROM public.reels;
  SELECT count(*) INTO v_tickets FROM public.user_support_tickets WHERE status = 'open';
  SELECT count(*) INTO v_reports FROM public.user_reports WHERE status = 'pending';
  SELECT count(*) INTO v_active_subs FROM public.subscriptions WHERE is_active = true AND status = 'active';

  RETURN json_build_object(
    'totalUsers', v_users,
    'verifiedUsers', v_verified,
    'restrictedUsers', v_restricted,
    'totalPosts', v_posts,
    'totalReels', v_reels,
    'openTickets', v_tickets,
    'pendingReports', v_reports,
    'activeSubscriptions', v_active_subs
  );
END;
$$;

-- Protect lifetime_blue_eligible inside sync_profile_verification
CREATE OR REPLACE FUNCTION public.sync_profile_verification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (TG_OP = 'DELETE') THEN
    UPDATE public.profiles
    SET is_verified = COALESCE(lifetime_blue_eligible, false),
        updated_at = now()
    WHERE id = OLD.user_id;
    RETURN OLD;
  ELSIF (NEW.is_active = true AND NEW.status = 'verified') THEN
    UPDATE public.profiles
    SET is_verified = true,
        lifetime_blue_eligible = CASE
          WHEN NEW.plan_type = 'lifetime_referral' THEN true
          ELSE lifetime_blue_eligible
        END,
        updated_at = now()
    WHERE id = NEW.user_id;
    RETURN NEW;
  ELSIF (NEW.status = 'expired') THEN
    UPDATE public.profiles
    SET is_verified = COALESCE(lifetime_blue_eligible, false),
        updated_at = now()
    WHERE id = NEW.user_id;
    RETURN NEW;
  ELSE
    UPDATE public.profiles
    SET is_verified = false,
        updated_at = now()
    WHERE id = NEW.user_id
      AND COALESCE(lifetime_blue_eligible, false) = false;
    RETURN NEW;
  END IF;
END;
$$;

-- Automated expiration RPC preserving lifetime_blue_eligible = true and expires_at IS NULL
CREATE OR REPLACE FUNCTION public.expire_stale_subscriptions()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expired_verifs int := 0;
  v_expired_subs int := 0;
  v_expired_restr int := 0;
BEGIN
  WITH exp_v AS (
    UPDATE public.user_verifications uv
    SET is_active = false,
        status = 'expired',
        updated_at = now()
    FROM public.profiles p
    WHERE uv.user_id = p.id
      AND uv.is_active = true
      AND uv.expires_at IS NOT NULL
      AND uv.expires_at < now()
      AND COALESCE(p.lifetime_blue_eligible, false) = false
    RETURNING uv.user_id
  ),
  upd_p AS (
    UPDATE public.profiles p
    SET is_verified = false,
        updated_at = now()
    WHERE p.id IN (SELECT user_id FROM exp_v)
      AND COALESCE(p.lifetime_blue_eligible, false) = false
    RETURNING p.id
  )
  SELECT count(*) INTO v_expired_verifs FROM upd_p;

  WITH exp_s AS (
    UPDATE public.subscriptions s
    SET is_active = false,
        status = 'expired',
        updated_at = now()
    FROM public.profiles p
    WHERE s.user_id = p.id
      AND s.is_active = true
      AND s.expires_at IS NOT NULL
      AND s.expires_at < now()
      AND COALESCE(p.lifetime_blue_eligible, false) = false
    RETURNING s.id
  )
  SELECT count(*) INTO v_expired_subs FROM exp_s;

  WITH exp_r AS (
    UPDATE public.user_restrictions
    SET status = 'expired'
    WHERE status = 'active'
      AND expires_at IS NOT NULL
      AND expires_at < now()
    RETURNING user_id
  ),
  lift_p AS (
    UPDATE public.profiles p
    SET is_restricted = false,
        restricted_until = NULL,
        restriction_reason = NULL,
        updated_at = now()
    WHERE p.id IN (SELECT DISTINCT user_id FROM exp_r)
      AND NOT EXISTS (
        SELECT 1 FROM public.user_restrictions ur
        WHERE ur.user_id = p.id
          AND ur.status = 'active'
          AND ur.type = 'RESTRICTION'
          AND (ur.expires_at IS NULL OR ur.expires_at > now())
      )
    RETURNING p.id
  )
  SELECT count(*) INTO v_expired_restr FROM lift_p;

  RETURN jsonb_build_object(
    'expired_verifications', v_expired_verifs,
    'expired_subscriptions', v_expired_subs,
    'lifted_restrictions', v_expired_restr
  );
END;
$$;

