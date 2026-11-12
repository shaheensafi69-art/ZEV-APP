-- Migration 012 UP: Content Experience — Hashtags Sync, Unified Search,
-- Explore/Discover RPCs, Post View Tracking, Story Close Friends & Reactions/Replies

BEGIN;

-- 1. Unique case-insensitive hashtag index & lookup indexes
CREATE UNIQUE INDEX IF NOT EXISTS uq_hashtags_lower_tag
  ON public.hashtags (lower(tag));

CREATE INDEX IF NOT EXISTS idx_hashtags_trending
  ON public.hashtags ((COALESCE(posts_count, 0) + COALESCE(reels_count, 0)) DESC, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_post_hashtags_hashtag
  ON public.post_hashtags (hashtag_id, post_id);

CREATE INDEX IF NOT EXISTS idx_reel_hashtags_hashtag
  ON public.reel_hashtags (hashtag_id, reel_id);

-- 2. Unique reaction per (story_id, user_id) & missing UPDATE/DELETE policies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.story_reactions'::regclass
      AND conname = 'uq_story_reactions_story_user'
  ) THEN
    DELETE FROM public.story_reactions sr
    USING public.story_reactions dup
    WHERE sr.story_id = dup.story_id
      AND sr.user_id = dup.user_id
      AND sr.ctid < dup.ctid;

    ALTER TABLE public.story_reactions
      ADD CONSTRAINT uq_story_reactions_story_user UNIQUE (story_id, user_id);
  END IF;
END $$;

DROP POLICY IF EXISTS story_reactions_update ON public.story_reactions;
CREATE POLICY story_reactions_update ON public.story_reactions
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.user_stories s
      WHERE s.id = story_reactions.story_id
        AND s.deleted_at IS NULL
        AND NOT public.is_blocked_between(auth.uid(), s.user_id)
    )
  );

DROP POLICY IF EXISTS story_reactions_delete ON public.story_reactions;
CREATE POLICY story_reactions_delete ON public.story_reactions
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Story Likes Select Policy" ON public.story_likes;
CREATE POLICY "Story Likes Select Policy" ON public.story_likes
  FOR SELECT TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.user_stories s
      WHERE s.id = story_likes.story_id AND s.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Story Likes Insert Policy" ON public.story_likes;
CREATE POLICY "Story Likes Insert Policy" ON public.story_likes
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.user_stories s
      WHERE s.id = story_likes.story_id
        AND s.deleted_at IS NULL
        AND NOT public.is_blocked_between(auth.uid(), s.user_id)
    )
  );

-- 3. Tighten user_stories SELECT policy with block & ban/status checks
DROP POLICY IF EXISTS user_stories_select_visible ON public.user_stories;
CREATE POLICY user_stories_select_visible ON public.user_stories
  FOR SELECT TO anon, authenticated
  USING (
    auth.uid() = user_id
    OR (
      deleted_at IS NULL
      AND expires_at > now()
      AND (auth.uid() IS NULL OR NOT public.is_blocked_between(auth.uid(), user_stories.user_id))
      AND EXISTS (
        SELECT 1 FROM public.profiles po
        WHERE po.id = user_stories.user_id
          AND COALESCE(po.is_banned, false) = false
          AND COALESCE(po.account_status, 'active') = 'active'
          AND (
            (
              COALESCE(user_stories.visibility, 'public') <> 'close_friends'
              AND (
                COALESCE(po.is_private, false) = false
                OR (
                  auth.uid() IS NOT NULL
                  AND EXISTS (
                    SELECT 1 FROM public.user_follows uf
                    WHERE uf.follower_id = auth.uid() AND uf.following_id = user_stories.user_id
                  )
                )
              )
            )
            OR (
              user_stories.visibility = 'close_friends'
              AND auth.uid() IS NOT NULL
              AND EXISTS (
                SELECT 1 FROM public.close_friends cf
                WHERE cf.user_id = user_stories.user_id AND cf.friend_id = auth.uid()
              )
            )
          )
      )
    )
  );

-- 4. Hashtag extraction & automatic sync triggers
CREATE OR REPLACE FUNCTION public.extract_hashtags(p_text text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  WITH cleaned AS (
    SELECT regexp_replace(COALESCE(p_text, ''), 'https?://\S+', ' ', 'gi') AS txt
  ),
  raw_matches AS (
    SELECT m[1] AS tag, ord
    FROM cleaned,
    LATERAL regexp_matches(
      cleaned.txt,
      U&'(?:^|[^[:alnum:]_])#([A-Za-z0-9_\0600-\06FF\0750-\077F\FB50-\FDFF\FE70-\FEFF]{1,64})',
      'g'
    ) WITH ORDINALITY AS t(m, ord)
  ),
  dedup AS (
    SELECT DISTINCT ON (lower(tag)) tag, ord
    FROM raw_matches
    WHERE length(tag) BETWEEN 1 AND 64
    ORDER BY lower(tag), ord ASC
  )
  SELECT COALESCE(array_agg(tag ORDER BY ord ASC), ARRAY[]::text[])
  FROM dedup;
$$;

CREATE OR REPLACE FUNCTION public.sync_content_hashtags(
  p_content_type text,
  p_content_id uuid,
  p_text text,
  p_is_active boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_tags text[];
  v_lower_tags text[];
  v_tag text;
  v_hashtag_ids uuid[];
BEGIN
  IF p_content_id IS NULL THEN
    RETURN;
  END IF;

  IF NOT COALESCE(p_is_active, false) THEN
    IF p_content_type = 'post' THEN
      DELETE FROM public.post_hashtags WHERE post_id = p_content_id;
    ELSIF p_content_type = 'reel' THEN
      DELETE FROM public.reel_hashtags WHERE reel_id = p_content_id;
    END IF;
    RETURN;
  END IF;

  v_tags := public.extract_hashtags(p_text);

  IF COALESCE(array_length(v_tags, 1), 0) = 0 THEN
    IF p_content_type = 'post' THEN
      DELETE FROM public.post_hashtags WHERE post_id = p_content_id;
    ELSIF p_content_type = 'reel' THEN
      DELETE FROM public.reel_hashtags WHERE reel_id = p_content_id;
    END IF;
    RETURN;
  END IF;

  FOREACH v_tag IN ARRAY v_tags LOOP
    INSERT INTO public.hashtags (tag)
    VALUES (v_tag)
    ON CONFLICT ((lower(tag))) DO NOTHING;
  END LOOP;

  SELECT array_agg(lower(t)) INTO v_lower_tags FROM unnest(v_tags) AS t;

  SELECT COALESCE(array_agg(h.id), ARRAY[]::uuid[])
  INTO v_hashtag_ids
  FROM public.hashtags h
  WHERE lower(h.tag) = ANY(v_lower_tags);

  IF p_content_type = 'post' THEN
    DELETE FROM public.post_hashtags
    WHERE post_id = p_content_id
      AND NOT (hashtag_id = ANY(v_hashtag_ids));

    INSERT INTO public.post_hashtags (post_id, hashtag_id)
    SELECT p_content_id, hid
    FROM unnest(v_hashtag_ids) AS hid
    ON CONFLICT (post_id, hashtag_id) DO NOTHING;
  ELSIF p_content_type = 'reel' THEN
    DELETE FROM public.reel_hashtags
    WHERE reel_id = p_content_id
      AND NOT (hashtag_id = ANY(v_hashtag_ids));

    INSERT INTO public.reel_hashtags (reel_id, hashtag_id)
    SELECT p_content_id, hid
    FROM unnest(v_hashtag_ids) AS hid
    ON CONFLICT (reel_id, hashtag_id) DO NOTHING;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_fn_sync_post_hashtags()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_active boolean;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.title IS NOT DISTINCT FROM NEW.title
     AND OLD.content IS NOT DISTINCT FROM NEW.content
     AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at
     AND OLD.is_draft IS NOT DISTINCT FROM NEW.is_draft THEN
    RETURN NEW;
  END IF;

  v_active := NEW.deleted_at IS NULL AND COALESCE(NEW.is_draft, false) = false;
  PERFORM public.sync_content_hashtags(
    'post',
    NEW.id,
    concat_ws(' ', NEW.title, NEW.content),
    v_active
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_fn_sync_reel_hashtags()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_active boolean;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.title IS NOT DISTINCT FROM NEW.title
     AND OLD.description IS NOT DISTINCT FROM NEW.description
     AND OLD.deleted_at IS NOT DISTINCT FROM NEW.deleted_at
     AND OLD.is_published IS NOT DISTINCT FROM NEW.is_published THEN
    RETURN NEW;
  END IF;

  v_active := NEW.deleted_at IS NULL AND COALESCE(NEW.is_published, true) = true;
  PERFORM public.sync_content_hashtags(
    'reel',
    NEW.id,
    concat_ws(' ', NEW.title, NEW.description),
    v_active
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_post_hashtags ON public.discussion_posts;
CREATE TRIGGER trg_sync_post_hashtags
  AFTER INSERT OR UPDATE ON public.discussion_posts
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_sync_post_hashtags();

DROP TRIGGER IF EXISTS trg_sync_reel_hashtags ON public.reels;
CREATE TRIGGER trg_sync_reel_hashtags
  AFTER INSERT OR UPDATE ON public.reels
  FOR EACH ROW EXECUTE FUNCTION public.trg_fn_sync_reel_hashtags();

-- Backfill hashtags on existing active posts & reels and reconcile counters
DO $$
DECLARE
  r_post RECORD;
  r_reel RECORD;
BEGIN
  FOR r_post IN
    SELECT id, title, content, deleted_at, is_draft FROM public.discussion_posts
  LOOP
    PERFORM public.sync_content_hashtags(
      'post',
      r_post.id,
      concat_ws(' ', r_post.title, r_post.content),
      r_post.deleted_at IS NULL AND COALESCE(r_post.is_draft, false) = false
    );
  END LOOP;

  FOR r_reel IN
    SELECT id, title, description, deleted_at, is_published FROM public.reels
  LOOP
    PERFORM public.sync_content_hashtags(
      'reel',
      r_reel.id,
      concat_ws(' ', r_reel.title, r_reel.description),
      r_reel.deleted_at IS NULL AND COALESCE(r_reel.is_published, true) = true
    );
  END LOOP;

  PERFORM public.reconcile_all_counters();
END $$;

-- 5. Post View Counter Trigger & Idempotent RPC
CREATE OR REPLACE FUNCTION public.trg_cnt_post_views()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.discussion_posts
    SET views_count = COALESCE(views_count, 0) + 1
    WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.discussion_posts
    SET views_count = GREATEST(0, COALESCE(views_count, 0) - 1)
    WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cnt_post_views ON public.post_views;
CREATE TRIGGER trg_cnt_post_views
  AFTER INSERT OR DELETE ON public.post_views
  FOR EACH ROW EXECUTE FUNCTION public.trg_cnt_post_views();

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

REVOKE ALL ON FUNCTION public.record_post_view(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_post_view(uuid) TO authenticated;

-- 6. Hardened Story Like / Reply / Reaction Notification Triggers
CREATE OR REPLACE FUNCTION public.notify_on_story_like()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_owner_id uuid;
BEGIN
  SELECT us.user_id INTO v_owner_id
  FROM public.user_stories us
  WHERE us.id = NEW.story_id AND us.deleted_at IS NULL;

  IF v_owner_id IS NOT NULL
     AND v_owner_id <> NEW.user_id
     AND NOT public.is_blocked_between(v_owner_id, NEW.user_id) THEN
    INSERT INTO public.user_notifications (
      user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
    ) VALUES (
      v_owner_id, NEW.user_id, 'Story Liked', 'liked your story.', 'story_like', NEW.story_id::text, false, 'zev', now()
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_on_story_reply()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_owner_id uuid;
  v_snippet text;
BEGIN
  SELECT us.user_id INTO v_owner_id
  FROM public.user_stories us
  WHERE us.id = NEW.story_id AND us.deleted_at IS NULL;

  IF v_owner_id IS NOT NULL
     AND v_owner_id <> NEW.sender_id
     AND NOT public.is_blocked_between(v_owner_id, NEW.sender_id) THEN
    v_snippet := left(trim(COALESCE(NEW.reply_text, '')), 120);
    INSERT INTO public.user_notifications (
      user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
    ) VALUES (
      v_owner_id,
      NEW.sender_id,
      'Story Reply',
      CASE WHEN v_snippet <> '' THEN 'replied to your story: "' || v_snippet || '"' ELSE 'replied to your story.' END,
      'story_reply',
      NEW.story_id::text,
      false,
      'zev',
      now()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_notify_story_reply ON public.story_replies;
CREATE TRIGGER tr_notify_story_reply
  AFTER INSERT ON public.story_replies
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_story_reply();

CREATE OR REPLACE FUNCTION public.notify_on_story_reaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_owner_id uuid;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.emoji IS NOT DISTINCT FROM NEW.emoji THEN
    RETURN NEW;
  END IF;

  SELECT us.user_id INTO v_owner_id
  FROM public.user_stories us
  WHERE us.id = NEW.story_id AND us.deleted_at IS NULL;

  IF v_owner_id IS NOT NULL
     AND v_owner_id <> NEW.user_id
     AND NOT public.is_blocked_between(v_owner_id, NEW.user_id) THEN
    INSERT INTO public.user_notifications (
      user_id, sender_id, title, message, notification_type, link_url, is_read, app_source, created_at
    ) VALUES (
      v_owner_id,
      NEW.user_id,
      'Story Reaction',
      'reacted ' || COALESCE(NEW.emoji, '❤️') || ' to your story.',
      'story_reaction',
      NEW.story_id::text,
      false,
      'zev',
      now()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_notify_story_reaction ON public.story_reactions;
CREATE TRIGGER tr_notify_story_reaction
  AFTER INSERT OR UPDATE OF emoji ON public.story_reactions
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_story_reaction();

-- 7. Trending Hashtags & Hashtag Feed RPCs
CREATE OR REPLACE FUNCTION public.get_trending_hashtags(
  p_limit integer DEFAULT 15
)
RETURNS TABLE (
  id uuid,
  tag text,
  posts_count integer,
  reels_count integer,
  total_count integer,
  updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 50);
BEGIN
  RETURN QUERY
  SELECT
    h.id,
    h.tag,
    COALESCE(h.posts_count, 0)::integer AS posts_count,
    COALESCE(h.reels_count, 0)::integer AS reels_count,
    (COALESCE(h.posts_count, 0) + COALESCE(h.reels_count, 0))::integer AS total_count,
    COALESCE(h.updated_at, h.created_at, now()) AS updated_at
  FROM public.hashtags h
  ORDER BY (COALESCE(h.posts_count, 0) + COALESCE(h.reels_count, 0)) DESC,
           COALESCE(h.updated_at, h.created_at) DESC,
           h.tag ASC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_trending_hashtags(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_trending_hashtags(integer) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.get_hashtag_content(
  p_tag text,
  p_limit integer DEFAULT 40
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 40), 1), 60);
  v_clean text := regexp_replace(trim(coalesce(p_tag, '')), '^#+', '');
  v_hashtag record;
  v_posts jsonb := '[]'::jsonb;
  v_reels jsonb := '[]'::jsonb;
BEGIN
  IF v_clean = '' THEN
    RETURN jsonb_build_object(
      'tag', '',
      'posts_count', 0,
      'reels_count', 0,
      'posts', '[]'::jsonb,
      'reels', '[]'::jsonb
    );
  END IF;

  SELECT h.id, h.tag, COALESCE(h.posts_count, 0) AS posts_count, COALESCE(h.reels_count, 0) AS reels_count
  INTO v_hashtag
  FROM public.hashtags h
  WHERE lower(h.tag) = lower(v_clean)
  LIMIT 1;

  IF v_hashtag.id IS NOT NULL THEN
    SELECT COALESCE(jsonb_agg(row_obj ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_posts
    FROM (
      SELECT
        dp.created_at,
        jsonb_build_object(
          'id', dp.id,
          'student_id', dp.student_id,
          'title', COALESCE(dp.title, ''),
          'content', COALESCE(dp.content, ''),
          'image_url', COALESCE(NULLIF(dp.image_url, ''), (
            SELECT pm.media_url FROM public.post_media pm
            WHERE pm.post_id = dp.id
            ORDER BY pm.sort_order ASC, pm.created_at ASC
            LIMIT 1
          ), ''),
          'post_type', COALESCE(dp.post_type, 'text'),
          'visibility', COALESCE(dp.visibility, 'public'),
          'location', COALESCE(dp.location, ''),
          'edited_at', dp.edited_at,
          'created_at', dp.created_at,
          'likes_count', COALESCE(dp.likes_count, 0),
          'comments_count', COALESCE(dp.comments_count, 0),
          'reposts_count', COALESCE(dp.reposts_count, 0),
          'bookmarks_count', COALESCE(dp.bookmarks_count, 0),
          'views_count', COALESCE(dp.views_count, 0),
          'author_username', COALESCE(pr.username, 'user'),
          'author_first_name', COALESCE(pr.first_name, ''),
          'author_last_name', COALESCE(pr.last_name, ''),
          'author_avatar_url', COALESCE(pr.avatar_url, ''),
          'author_is_verified', COALESCE(pr.is_verified, false),
          'is_liked_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.discussion_likes dl WHERE dl.post_id = dp.id AND dl.student_id = v_me
          ) END,
          'is_reposted_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.post_reposts rep WHERE rep.post_id = dp.id AND rep.user_id = v_me
          ) END,
          'is_bookmarked_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.discussion_bookmarks dbm WHERE dbm.post_id = dp.id AND dbm.user_id = v_me
          ) END,
          'is_author_followed', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
          ) END,
          'media_items', COALESCE((
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
            FROM public.post_media pm WHERE pm.post_id = dp.id
          ), '[]'::jsonb)
        ) AS row_obj
      FROM public.post_hashtags ph
      JOIN public.discussion_posts dp ON dp.id = ph.post_id
      JOIN public.profiles pr ON pr.id = dp.student_id
      WHERE ph.hashtag_id = v_hashtag.id
        AND dp.deleted_at IS NULL
        AND COALESCE(dp.is_draft, false) = false
        AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
        AND COALESCE(pr.is_banned, false) = false
        AND COALESCE(pr.account_status, 'active') = 'active'
        AND (
          v_me = dp.student_id
          OR (
            COALESCE(dp.visibility, 'public') <> 'private'
            AND (
              (COALESCE(pr.is_private, false) = false AND COALESCE(dp.visibility, 'public') <> 'followers')
              OR (v_me IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
              ))
            )
          )
        )
        AND (
          v_me IS NULL
          OR (
            NOT public.is_blocked_between(v_me, dp.student_id)
            AND NOT EXISTS (
              SELECT 1 FROM public.user_mutes um
              WHERE um.muter_id = v_me AND um.muted_id = dp.student_id AND COALESCE(um.mute_posts, true) = true
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.hidden_posts hp
              WHERE hp.user_id = v_me AND hp.target_type = 'post' AND hp.target_id = dp.id
            )
          )
        )
      ORDER BY dp.created_at DESC
      LIMIT v_limit
    ) sub_posts;

    SELECT COALESCE(jsonb_agg(row_obj ORDER BY created_at DESC), '[]'::jsonb)
    INTO v_reels
    FROM (
      SELECT
        r.created_at,
        jsonb_build_object(
          'id', r.id,
          'user_id', r.user_id,
          'title', COALESCE(r.title, ''),
          'description', COALESCE(r.description, ''),
          'video_url', COALESCE(r.video_url, ''),
          'thumbnail_url', r.thumbnail_url,
          'category', COALESCE(r.category, 'Explore'),
          'audio_name', COALESCE(r.audio_name, ''),
          'duration_seconds', COALESCE(r.duration_seconds, 0),
          'views_count', COALESCE(r.views_count, 0),
          'likes_count', COALESCE(r.likes_count, 0),
          'comments_count', COALESCE(r.comments_count, 0),
          'created_at', r.created_at,
          'author_username', COALESCE(pr.username, 'creator'),
          'author_first_name', COALESCE(pr.first_name, ''),
          'author_last_name', COALESCE(pr.last_name, ''),
          'author_avatar_url', COALESCE(pr.avatar_url, ''),
          'author_is_verified', COALESCE(pr.is_verified, false),
          'is_liked_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.reel_likes rl WHERE rl.reel_id = r.id AND rl.user_id = v_me
          ) END,
          'is_bookmarked_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.reel_bookmarks rb WHERE rb.reel_id = r.id AND rb.user_id = v_me
          ) END,
          'is_author_followed', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
          ) END
        ) AS row_obj
      FROM public.reel_hashtags rh
      JOIN public.reels r ON r.id = rh.reel_id
      JOIN public.profiles pr ON pr.id = r.user_id
      WHERE rh.hashtag_id = v_hashtag.id
        AND r.deleted_at IS NULL
        AND COALESCE(r.is_published, true) = true
        AND COALESCE(pr.is_banned, false) = false
        AND COALESCE(pr.account_status, 'active') = 'active'
        AND (
          v_me = r.user_id
          OR (
            COALESCE(r.visibility, 'public') <> 'private'
            AND (
              (COALESCE(pr.is_private, false) = false AND COALESCE(r.visibility, 'public') <> 'followers')
              OR (v_me IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
              ))
            )
          )
        )
        AND (
          v_me IS NULL
          OR (
            NOT public.is_blocked_between(v_me, r.user_id)
            AND NOT EXISTS (
              SELECT 1 FROM public.user_mutes um
              WHERE um.muter_id = v_me AND um.muted_id = r.user_id AND COALESCE(um.mute_posts, true) = true
            )
            AND NOT EXISTS (
              SELECT 1 FROM public.hidden_posts hp
              WHERE hp.user_id = v_me AND hp.target_type = 'reel' AND hp.target_id = r.id
            )
          )
        )
      ORDER BY r.created_at DESC
      LIMIT v_limit
    ) sub_reels;
  END IF;

  RETURN jsonb_build_object(
    'tag', COALESCE(v_hashtag.tag, v_clean),
    'posts_count', COALESCE(v_hashtag.posts_count, 0),
    'reels_count', COALESCE(v_hashtag.reels_count, 0),
    'posts', v_posts,
    'reels', v_reels
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_hashtag_content(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_hashtag_content(text, integer) TO authenticated, anon;

-- 8. Unified Search RPC & Search History Management RPCs
CREATE OR REPLACE FUNCTION public.search_unified_content(
  p_query text,
  p_limit integer DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 40);
  v_raw text := trim(coalesce(p_query, ''));
  v_user_q text;
  v_tag_q text;
  v_esc_raw text;
  v_esc_user text;
  v_esc_tag text;
  v_accounts jsonb := '[]'::jsonb;
  v_reels jsonb := '[]'::jsonb;
  v_posts jsonb := '[]'::jsonb;
  v_hashtags jsonb := '[]'::jsonb;
BEGIN
  IF v_raw = '' THEN
    RETURN jsonb_build_object(
      'accounts', '[]'::jsonb,
      'reels', '[]'::jsonb,
      'posts', '[]'::jsonb,
      'hashtags', '[]'::jsonb
    );
  END IF;

  v_user_q := regexp_replace(v_raw, '^@+', '');
  v_tag_q := regexp_replace(v_raw, '^#+', '');
  v_esc_raw := replace(replace(replace(v_raw, '\', '\\'), '%', '\%'), '_', '\_');
  v_esc_user := replace(replace(replace(v_user_q, '\', '\\'), '%', '\%'), '_', '\_');
  v_esc_tag := replace(replace(replace(v_tag_q, '\', '\\'), '%', '\%'), '_', '\_');

  -- Accounts
  IF v_user_q <> '' THEN
    SELECT COALESCE(jsonb_agg(obj ORDER BY rank_exact DESC, followers_cnt DESC, uname ASC), '[]'::jsonb)
    INTO v_accounts
    FROM (
      SELECT
        pr.username AS uname,
        COALESCE(pr.followers_count, 0) AS followers_cnt,
        CASE
          WHEN lower(COALESCE(pr.username, '')) = lower(v_user_q) THEN 3
          WHEN COALESCE(pr.username, '') ILIKE (v_esc_user || '%') ESCAPE '\' THEN 2
          ELSE 1
        END AS rank_exact,
        jsonb_build_object(
          'id', pr.id,
          'username', COALESCE(pr.username, 'user'),
          'first_name', COALESCE(pr.first_name, ''),
          'last_name', COALESCE(pr.last_name, ''),
          'avatar_url', COALESCE(pr.avatar_url, ''),
          'is_verified', COALESCE(pr.is_verified, false),
          'is_private', COALESCE(pr.is_private, false),
          'bio', COALESCE(pr.bio, ''),
          'followers_count', COALESCE(pr.followers_count, 0),
          'is_following', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = pr.id
          ) END,
          'is_requested', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
            SELECT 1 FROM public.follow_requests fr WHERE fr.requester_id = v_me AND fr.target_id = pr.id AND fr.status = 'pending'
          ) END
        ) AS obj
      FROM public.profiles pr
      WHERE COALESCE(pr.is_banned, false) = false
        AND COALESCE(pr.account_status, 'active') = 'active'
        AND (v_me IS NULL OR (pr.id <> v_me AND NOT public.is_blocked_between(v_me, pr.id)))
        AND (
          COALESCE(pr.username, '') ILIKE ('%' || v_esc_user || '%') ESCAPE '\'
          OR COALESCE(pr.first_name, '') ILIKE ('%' || v_esc_user || '%') ESCAPE '\'
          OR COALESCE(pr.last_name, '') ILIKE ('%' || v_esc_user || '%') ESCAPE '\'
          OR COALESCE(pr.bio, '') ILIKE ('%' || v_esc_user || '%') ESCAPE '\'
        )
      ORDER BY rank_exact DESC, followers_cnt DESC, uname ASC
      LIMIT v_limit
    ) acc_sub;
  END IF;

  -- Reels
  SELECT COALESCE(jsonb_agg(obj ORDER BY views_cnt DESC, created_at DESC), '[]'::jsonb)
  INTO v_reels
  FROM (
    SELECT
      r.created_at,
      COALESCE(r.views_count, 0) AS views_cnt,
      jsonb_build_object(
        'id', r.id,
        'user_id', r.user_id,
        'title', COALESCE(r.title, ''),
        'description', COALESCE(r.description, ''),
        'video_url', COALESCE(r.video_url, ''),
        'thumbnail_url', r.thumbnail_url,
        'category', COALESCE(r.category, 'Explore'),
        'audio_name', COALESCE(r.audio_name, ''),
        'duration_seconds', COALESCE(r.duration_seconds, 0),
        'views_count', COALESCE(r.views_count, 0),
        'likes_count', COALESCE(r.likes_count, 0),
        'comments_count', COALESCE(r.comments_count, 0),
        'created_at', r.created_at,
        'author_username', COALESCE(pr.username, 'creator'),
        'author_first_name', COALESCE(pr.first_name, ''),
        'author_last_name', COALESCE(pr.last_name, ''),
        'author_avatar_url', COALESCE(pr.avatar_url, ''),
        'author_is_verified', COALESCE(pr.is_verified, false),
        'is_liked_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
          SELECT 1 FROM public.reel_likes rl WHERE rl.reel_id = r.id AND rl.user_id = v_me
        ) END,
        'is_bookmarked_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
          SELECT 1 FROM public.reel_bookmarks rb WHERE rb.reel_id = r.id AND rb.user_id = v_me
        ) END,
        'is_author_followed', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
          SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
        ) END
      ) AS obj
    FROM public.reels r
    JOIN public.profiles pr ON pr.id = r.user_id
    WHERE r.deleted_at IS NULL
      AND COALESCE(r.is_published, true) = true
      AND COALESCE(pr.is_banned, false) = false
      AND COALESCE(pr.account_status, 'active') = 'active'
      AND (
        v_me = r.user_id
        OR (
          COALESCE(r.visibility, 'public') <> 'private'
          AND (
            (COALESCE(pr.is_private, false) = false AND COALESCE(r.visibility, 'public') <> 'followers')
            OR (v_me IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
            ))
          )
        )
      )
      AND (
        v_me IS NULL
        OR (
          NOT public.is_blocked_between(v_me, r.user_id)
          AND NOT EXISTS (
            SELECT 1 FROM public.user_mutes um
            WHERE um.muter_id = v_me AND um.muted_id = r.user_id AND COALESCE(um.mute_posts, true) = true
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.hidden_posts hp
            WHERE hp.user_id = v_me AND hp.target_type = 'reel' AND hp.target_id = r.id
          )
        )
      )
      AND (
        COALESCE(r.title, '') ILIKE ('%' || v_esc_raw || '%') ESCAPE '\'
        OR COALESCE(r.description, '') ILIKE ('%' || v_esc_raw || '%') ESCAPE '\'
        OR COALESCE(r.category, '') ILIKE ('%' || v_esc_raw || '%') ESCAPE '\'
        OR COALESCE(pr.username, '') ILIKE ('%' || v_esc_user || '%') ESCAPE '\'
        OR (
          v_tag_q <> '' AND EXISTS (
            SELECT 1 FROM public.reel_hashtags rh
            JOIN public.hashtags h ON h.id = rh.hashtag_id
            WHERE rh.reel_id = r.id AND h.tag ILIKE ('%' || v_esc_tag || '%') ESCAPE '\'
          )
        )
      )
    ORDER BY COALESCE(r.views_count, 0) DESC, r.created_at DESC
    LIMIT v_limit
  ) reel_sub;

  -- Posts
  SELECT COALESCE(jsonb_agg(obj ORDER BY likes_cnt DESC, created_at DESC), '[]'::jsonb)
  INTO v_posts
  FROM (
    SELECT
      dp.created_at,
      COALESCE(dp.likes_count, 0) AS likes_cnt,
      jsonb_build_object(
        'id', dp.id,
        'student_id', dp.student_id,
        'title', COALESCE(dp.title, ''),
        'content', COALESCE(dp.content, ''),
        'image_url', COALESCE(NULLIF(dp.image_url, ''), (
          SELECT pm.media_url FROM public.post_media pm
          WHERE pm.post_id = dp.id
          ORDER BY pm.sort_order ASC, pm.created_at ASC
          LIMIT 1
        ), ''),
        'post_type', COALESCE(dp.post_type, 'text'),
        'visibility', COALESCE(dp.visibility, 'public'),
        'location', COALESCE(dp.location, ''),
        'edited_at', dp.edited_at,
        'created_at', dp.created_at,
        'likes_count', COALESCE(dp.likes_count, 0),
        'comments_count', COALESCE(dp.comments_count, 0),
        'reposts_count', COALESCE(dp.reposts_count, 0),
        'bookmarks_count', COALESCE(dp.bookmarks_count, 0),
        'views_count', COALESCE(dp.views_count, 0),
        'author_username', COALESCE(pr.username, 'user'),
        'author_first_name', COALESCE(pr.first_name, ''),
        'author_last_name', COALESCE(pr.last_name, ''),
        'author_avatar_url', COALESCE(pr.avatar_url, ''),
        'author_is_verified', COALESCE(pr.is_verified, false),
        'is_liked_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
          SELECT 1 FROM public.discussion_likes dl WHERE dl.post_id = dp.id AND dl.student_id = v_me
        ) END,
        'is_reposted_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
          SELECT 1 FROM public.post_reposts rep WHERE rep.post_id = dp.id AND rep.user_id = v_me
        ) END,
        'is_bookmarked_by_me', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
          SELECT 1 FROM public.discussion_bookmarks dbm WHERE dbm.post_id = dp.id AND dbm.user_id = v_me
        ) END,
        'is_author_followed', CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
          SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
        ) END,
        'media_items', COALESCE((
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
          FROM public.post_media pm WHERE pm.post_id = dp.id
        ), '[]'::jsonb)
      ) AS obj
    FROM public.discussion_posts dp
    JOIN public.profiles pr ON pr.id = dp.student_id
    WHERE dp.deleted_at IS NULL
      AND COALESCE(dp.is_draft, false) = false
      AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
      AND COALESCE(pr.is_banned, false) = false
      AND COALESCE(pr.account_status, 'active') = 'active'
      AND (
        v_me = dp.student_id
        OR (
          COALESCE(dp.visibility, 'public') <> 'private'
          AND (
            (COALESCE(pr.is_private, false) = false AND COALESCE(dp.visibility, 'public') <> 'followers')
            OR (v_me IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
            ))
          )
        )
      )
      AND (
        v_me IS NULL
        OR (
          NOT public.is_blocked_between(v_me, dp.student_id)
          AND NOT EXISTS (
            SELECT 1 FROM public.user_mutes um
            WHERE um.muter_id = v_me AND um.muted_id = dp.student_id AND COALESCE(um.mute_posts, true) = true
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.hidden_posts hp
            WHERE hp.user_id = v_me AND hp.target_type = 'post' AND hp.target_id = dp.id
          )
        )
      )
      AND (
        COALESCE(dp.title, '') ILIKE ('%' || v_esc_raw || '%') ESCAPE '\'
        OR COALESCE(dp.content, '') ILIKE ('%' || v_esc_raw || '%') ESCAPE '\'
        OR COALESCE(dp.location, '') ILIKE ('%' || v_esc_raw || '%') ESCAPE '\'
        OR (
          v_tag_q <> '' AND EXISTS (
            SELECT 1 FROM public.post_hashtags ph
            JOIN public.hashtags h ON h.id = ph.hashtag_id
            WHERE ph.post_id = dp.id AND h.tag ILIKE ('%' || v_esc_tag || '%') ESCAPE '\'
          )
        )
      )
    ORDER BY COALESCE(dp.likes_count, 0) DESC, dp.created_at DESC
    LIMIT v_limit
  ) post_sub;

  -- Hashtags
  IF v_tag_q <> '' THEN
    SELECT COALESCE(jsonb_agg(obj ORDER BY tot DESC, tname ASC), '[]'::jsonb)
    INTO v_hashtags
    FROM (
      SELECT
        h.tag AS tname,
        (COALESCE(h.posts_count, 0) + COALESCE(h.reels_count, 0)) AS tot,
        jsonb_build_object(
          'id', h.id,
          'tag', h.tag,
          'posts_count', COALESCE(h.posts_count, 0),
          'reels_count', COALESCE(h.reels_count, 0),
          'total_count', (COALESCE(h.posts_count, 0) + COALESCE(h.reels_count, 0))
        ) AS obj
      FROM public.hashtags h
      WHERE h.tag ILIKE ('%' || v_esc_tag || '%') ESCAPE '\'
      ORDER BY (COALESCE(h.posts_count, 0) + COALESCE(h.reels_count, 0)) DESC, h.tag ASC
      LIMIT v_limit
    ) tag_sub;
  END IF;

  RETURN jsonb_build_object(
    'accounts', v_accounts,
    'reels', v_reels,
    'posts', v_posts,
    'hashtags', v_hashtags
  );
END;
$$;

REVOKE ALL ON FUNCTION public.search_unified_content(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.search_unified_content(text, integer) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.save_search_history(
  p_query text,
  p_search_type text DEFAULT 'all',
  p_target_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_clean text := left(trim(coalesce(p_query, '')), 120);
  v_type text := COALESCE(NULLIF(trim(coalesce(p_search_type, 'all')), ''), 'all');
BEGIN
  IF v_me IS NULL OR v_clean = '' THEN
    RETURN;
  END IF;

  INSERT INTO public.search_history (user_id, query, search_type, target_id, created_at, updated_at)
  VALUES (v_me, v_clean, v_type, p_target_id, now(), now())
  ON CONFLICT (user_id, query, search_type)
  DO UPDATE SET
    updated_at = now(),
    target_id = COALESCE(EXCLUDED.target_id, public.search_history.target_id);

  DELETE FROM public.search_history
  WHERE id IN (
    SELECT id FROM public.search_history
    WHERE user_id = v_me
    ORDER BY updated_at DESC
    OFFSET 30
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_search_history(text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_search_history(text, text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_recent_searches(
  p_limit integer DEFAULT 15
)
RETURNS TABLE (
  id uuid,
  query text,
  search_type text,
  target_id uuid,
  updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 15), 1), 30);
BEGIN
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT sh.id, sh.query, sh.search_type, sh.target_id, sh.updated_at
  FROM public.search_history sh
  WHERE sh.user_id = v_me
  ORDER BY sh.updated_at DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_recent_searches(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_recent_searches(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.clear_search_history(
  p_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  IF p_id IS NULL THEN
    DELETE FROM public.search_history WHERE user_id = v_me;
  ELSE
    DELETE FROM public.search_history WHERE id = p_id AND user_id = v_me;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.clear_search_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_search_history(uuid) TO authenticated;

-- 9. Privacy/Safety-Compliant Explore Grid RPC
CREATE OR REPLACE FUNCTION public.get_explore_grid_page(
  p_category text DEFAULT NULL,
  p_offset integer DEFAULT 0,
  p_limit integer DEFAULT 36
)
RETURNS TABLE (
  item_id text,
  raw_id uuid,
  item_type text,
  media_url text,
  thumbnail_url text,
  title text,
  description text,
  category text,
  author_id uuid,
  author_username text,
  author_first_name text,
  author_last_name text,
  author_avatar_url text,
  author_is_verified boolean,
  views_count integer,
  likes_count integer,
  comments_count integer,
  reposts_count integer,
  created_at timestamptz,
  is_liked_by_me boolean,
  is_bookmarked_by_me boolean,
  is_reposted_by_me boolean,
  is_author_followed boolean,
  score double precision
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 36), 1), 60);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_cat text := lower(trim(coalesce(p_category, '')));
  v_esc_cat text := replace(replace(replace(v_cat, '\', '\\'), '%', '\%'), '_', '\_');
BEGIN
  RETURN QUERY
  WITH combined AS (
    SELECT
      'reel_' || r.id::text AS item_id,
      r.id AS raw_id,
      'reel'::text AS item_type,
      COALESCE(r.video_url, '') AS media_url,
      r.thumbnail_url AS thumbnail_url,
      COALESCE(r.title, '') AS title,
      COALESCE(r.description, '') AS description,
      COALESCE(r.category, 'Explore') AS category,
      r.user_id AS author_id,
      COALESCE(pr.username, 'creator') AS author_username,
      COALESCE(pr.first_name, '') AS author_first_name,
      COALESCE(pr.last_name, '') AS author_last_name,
      COALESCE(pr.avatar_url, '') AS author_avatar_url,
      COALESCE(pr.is_verified, false) AS author_is_verified,
      COALESCE(r.views_count, 0) AS views_count,
      COALESCE(r.likes_count, 0) AS likes_count,
      COALESCE(r.comments_count, 0) AS comments_count,
      0 AS reposts_count,
      r.created_at,
      CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM public.reel_likes rl WHERE rl.reel_id = r.id AND rl.user_id = v_me
      ) END AS is_liked_by_me,
      CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM public.reel_bookmarks rb WHERE rb.reel_id = r.id AND rb.user_id = v_me
      ) END AS is_bookmarked_by_me,
      false AS is_reposted_by_me,
      CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
      ) END AS is_author_followed,
      (
        (COALESCE(r.likes_count, 0) * 3.0 + COALESCE(r.comments_count, 0) * 4.0 + COALESCE(r.views_count, 0) * 0.25)
        + (100.0 / (1.0 + GREATEST(0.0, EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600.0) * 0.05))
      )::double precision AS score
    FROM public.reels r
    JOIN public.profiles pr ON pr.id = r.user_id
    WHERE r.deleted_at IS NULL
      AND COALESCE(r.is_published, true) = true
      AND COALESCE(r.video_url, '') <> ''
      AND COALESCE(pr.is_banned, false) = false
      AND COALESCE(pr.account_status, 'active') = 'active'
      AND (
        v_me = r.user_id
        OR (
          COALESCE(r.visibility, 'public') <> 'private'
          AND (
            (COALESCE(pr.is_private, false) = false AND COALESCE(r.visibility, 'public') <> 'followers')
            OR (v_me IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = r.user_id
            ))
          )
        )
      )
      AND (
        v_me IS NULL
        OR (
          NOT public.is_blocked_between(v_me, r.user_id)
          AND NOT EXISTS (
            SELECT 1 FROM public.user_mutes um
            WHERE um.muter_id = v_me AND um.muted_id = r.user_id AND COALESCE(um.mute_posts, true) = true
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.hidden_posts hp
            WHERE hp.user_id = v_me AND hp.target_type = 'reel' AND hp.target_id = r.id
          )
        )
      )

    UNION ALL

    SELECT
      'post_' || dp.id::text AS item_id,
      dp.id AS raw_id,
      'post'::text AS item_type,
      COALESCE(NULLIF(dp.image_url, ''), (
        SELECT pm.media_url FROM public.post_media pm
        WHERE pm.post_id = dp.id
        ORDER BY pm.sort_order ASC, pm.created_at ASC
        LIMIT 1
      ), '') AS media_url,
      COALESCE(NULLIF(dp.image_url, ''), (
        SELECT COALESCE(pm.thumbnail_url, pm.media_url) FROM public.post_media pm
        WHERE pm.post_id = dp.id
        ORDER BY pm.sort_order ASC, pm.created_at ASC
        LIMIT 1
      )) AS thumbnail_url,
      COALESCE(dp.title, '') AS title,
      COALESCE(dp.content, '') AS description,
      'Post'::text AS category,
      dp.student_id AS author_id,
      COALESCE(pr.username, 'user') AS author_username,
      COALESCE(pr.first_name, '') AS author_first_name,
      COALESCE(pr.last_name, '') AS author_last_name,
      COALESCE(pr.avatar_url, '') AS author_avatar_url,
      COALESCE(pr.is_verified, false) AS author_is_verified,
      COALESCE(dp.views_count, 0) AS views_count,
      COALESCE(dp.likes_count, 0) AS likes_count,
      COALESCE(dp.comments_count, 0) AS comments_count,
      COALESCE(dp.reposts_count, 0) AS reposts_count,
      dp.created_at,
      CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM public.discussion_likes dl WHERE dl.post_id = dp.id AND dl.student_id = v_me
      ) END AS is_liked_by_me,
      CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM public.discussion_bookmarks dbm WHERE dbm.post_id = dp.id AND dbm.user_id = v_me
      ) END AS is_bookmarked_by_me,
      CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM public.post_reposts rep WHERE rep.post_id = dp.id AND rep.user_id = v_me
      ) END AS is_reposted_by_me,
      CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
        SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
      ) END AS is_author_followed,
      (
        (COALESCE(dp.likes_count, 0) * 3.0 + COALESCE(dp.comments_count, 0) * 4.0 + COALESCE(dp.reposts_count, 0) * 3.5)
        + (95.0 / (1.0 + GREATEST(0.0, EXTRACT(EPOCH FROM (now() - dp.created_at)) / 3600.0) * 0.06))
      )::double precision AS score
    FROM public.discussion_posts dp
    JOIN public.profiles pr ON pr.id = dp.student_id
    WHERE dp.deleted_at IS NULL
      AND COALESCE(dp.is_draft, false) = false
      AND (dp.scheduled_at IS NULL OR dp.scheduled_at <= now())
      AND COALESCE(pr.is_banned, false) = false
      AND COALESCE(pr.account_status, 'active') = 'active'
      AND (
        COALESCE(dp.image_url, '') <> ''
        OR EXISTS (SELECT 1 FROM public.post_media pm WHERE pm.post_id = dp.id)
      )
      AND (
        v_me = dp.student_id
        OR (
          COALESCE(dp.visibility, 'public') <> 'private'
          AND (
            (COALESCE(pr.is_private, false) = false AND COALESCE(dp.visibility, 'public') <> 'followers')
            OR (v_me IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = dp.student_id
            ))
          )
        )
      )
      AND (
        v_me IS NULL
        OR (
          NOT public.is_blocked_between(v_me, dp.student_id)
          AND NOT EXISTS (
            SELECT 1 FROM public.user_mutes um
            WHERE um.muter_id = v_me AND um.muted_id = dp.student_id AND COALESCE(um.mute_posts, true) = true
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.hidden_posts hp
            WHERE hp.user_id = v_me AND hp.target_type = 'post' AND hp.target_id = dp.id
          )
        )
      )
  )
  SELECT c.*
  FROM combined c
  WHERE (
    v_cat = '' OR v_cat = 'for you' OR v_cat = 'trending'
    OR (v_cat = 'reels' AND c.item_type = 'reel')
    OR (v_cat = 'posts' AND c.item_type = 'post')
    OR (v_cat = 'technology' AND (c.category || ' ' || c.title || ' ' || c.description) ~* '(tech|code|software|\mai\M|app|dev|program|flutter|python|computer|robot|web)')
    OR (v_cat = 'design & art' AND (c.category || ' ' || c.title || ' ' || c.description) ~* '(design|art|draw|\mui\M|\mux\M|creative|paint|color|sketch|illustrat)')
    OR (v_cat = 'photography' AND (c.category || ' ' || c.title || ' ' || c.description) ~* '(photo|camera|shot|lens|pic|portrait|landscape|nature|capture)')
    OR (v_cat = 'fitness' AND (c.category || ' ' || c.title || ' ' || c.description) ~* '(fit|gym|workout|exercise|health|body|muscle|train|run|sport)')
    OR (v_cat = 'travel' AND (c.category || ' ' || c.title || ' ' || c.description) ~* '(travel|trip|tour|vacation|city|country|hotel|beach|mountain)')
    OR (v_cat = 'music' AND (c.category || ' ' || c.title || ' ' || c.description) ~* '(music|song|audio|sound|beat|voice|sing|track|guitar|melody)')
    OR (v_cat = 'quotes' AND (c.category || ' ' || c.title || ' ' || c.description) ~* '(quote|word|life|motivat|success|love|mind|lesson|wisdom)')
    OR lower(c.category) LIKE ('%' || v_esc_cat || '%') ESCAPE '\'
    OR lower(c.title || ' ' || c.description) LIKE ('%' || v_esc_cat || '%') ESCAPE '\'
  )
  ORDER BY c.score DESC, c.created_at DESC
  OFFSET v_offset
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_explore_grid_page(text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_explore_grid_page(text, integer, integer) TO authenticated, anon;

-- 10. Discover Creators RPC (with Recent Media Thumbnails & Follow/Request State)
CREATE OR REPLACE FUNCTION public.get_discover_creators(
  p_tab text DEFAULT 'Suggested',
  p_query text DEFAULT '',
  p_limit integer DEFAULT 40
)
RETURNS TABLE (
  id uuid,
  username text,
  first_name text,
  last_name text,
  avatar_url text,
  is_verified boolean,
  is_private boolean,
  bio text,
  followers_count integer,
  posts_count integer,
  reels_count integer,
  created_at timestamptz,
  is_following boolean,
  is_requested boolean,
  media_thumbnails jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 40), 1), 60);
  v_tab text := lower(trim(coalesce(p_tab, 'suggested')));
  v_raw_q text := trim(coalesce(p_query, ''));
  v_esc_q text := replace(replace(replace(v_raw_q, '\', '\\'), '%', '\%'), '_', '\_');
BEGIN
  RETURN QUERY
  SELECT
    pr.id,
    COALESCE(pr.username, 'user') AS username,
    COALESCE(pr.first_name, '') AS first_name,
    COALESCE(pr.last_name, '') AS last_name,
    COALESCE(pr.avatar_url, '') AS avatar_url,
    COALESCE(pr.is_verified, false) AS is_verified,
    COALESCE(pr.is_private, false) AS is_private,
    COALESCE(pr.bio, '') AS bio,
    COALESCE(pr.followers_count, 0) AS followers_count,
    COALESCE(pr.posts_count, 0) AS posts_count,
    COALESCE(pr.reels_count, 0) AS reels_count,
    pr.created_at,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = pr.id
    ) END AS is_following,
    CASE WHEN v_me IS NULL THEN false ELSE EXISTS (
      SELECT 1 FROM public.follow_requests fr WHERE fr.requester_id = v_me AND fr.target_id = pr.id AND fr.status = 'pending'
    ) END AS is_requested,
    CASE
      WHEN COALESCE(pr.is_private, false) = false
           OR (v_me IS NOT NULL AND EXISTS (
             SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = pr.id
           ))
      THEN COALESCE((
        SELECT jsonb_agg(m2.thumb ORDER BY m2.dt DESC)
        FROM (
          SELECT thumb, dt
          FROM (
            (
              SELECT COALESCE(NULLIF(dp.image_url, ''), (
                SELECT COALESCE(pm.thumbnail_url, pm.media_url)
                FROM public.post_media pm
                WHERE pm.post_id = dp.id
                ORDER BY pm.sort_order ASC, pm.created_at ASC
                LIMIT 1
              )) AS thumb, dp.created_at AS dt
              FROM public.discussion_posts dp
              WHERE dp.student_id = pr.id
                AND dp.deleted_at IS NULL
                AND COALESCE(dp.is_draft, false) = false
                AND COALESCE(dp.visibility, 'public') = 'public'
                AND (
                  COALESCE(dp.image_url, '') <> ''
                  OR EXISTS (SELECT 1 FROM public.post_media pm WHERE pm.post_id = dp.id)
                )
              ORDER BY dp.created_at DESC
              LIMIT 3
            )
            UNION ALL
            (
              SELECT r.thumbnail_url AS thumb, r.created_at AS dt
              FROM public.reels r
              WHERE r.user_id = pr.id
                AND r.deleted_at IS NULL
                AND COALESCE(r.is_published, true) = true
                AND COALESCE(r.visibility, 'public') = 'public'
                AND COALESCE(r.thumbnail_url, '') <> ''
              ORDER BY r.created_at DESC
              LIMIT 3
            )
          ) m
          WHERE COALESCE(m.thumb, '') <> ''
          ORDER BY m.dt DESC
          LIMIT 3
        ) m2
      ), '[]'::jsonb)
      ELSE '[]'::jsonb
    END AS media_thumbnails
  FROM public.profiles pr
  WHERE COALESCE(pr.is_banned, false) = false
    AND COALESCE(pr.account_status, 'active') = 'active'
    AND (v_me IS NULL OR (pr.id <> v_me AND NOT public.is_blocked_between(v_me, pr.id)))
    AND (
      v_raw_q = ''
      OR COALESCE(pr.username, '') ILIKE ('%' || v_esc_q || '%') ESCAPE '\'
      OR COALESCE(pr.first_name, '') ILIKE ('%' || v_esc_q || '%') ESCAPE '\'
      OR COALESCE(pr.last_name, '') ILIKE ('%' || v_esc_q || '%') ESCAPE '\'
      OR COALESCE(pr.bio, '') ILIKE ('%' || v_esc_q || '%') ESCAPE '\'
    )
    AND (
      v_tab <> 'verified'
      OR COALESCE(pr.is_verified, false) = true
    )
    AND (
      v_tab <> 'popular'
      OR COALESCE(pr.is_verified, false) = true
      OR COALESCE(pr.followers_count, 0) > 0
      OR length(COALESCE(pr.bio, '')) > 15
    )
  ORDER BY
    CASE WHEN v_tab = 'new' THEN pr.created_at END DESC NULLS LAST,
    CASE WHEN v_tab = 'popular' THEN (COALESCE(pr.followers_count, 0) + COALESCE(pr.posts_count, 0) * 2 + COALESCE(pr.reels_count, 0) * 3) END DESC NULLS LAST,
    COALESCE(pr.is_verified, false) DESC,
    (COALESCE(pr.followers_count, 0) + COALESCE(pr.posts_count, 0) + COALESCE(pr.reels_count, 0)) DESC,
    pr.created_at DESC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.get_discover_creators(text, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_discover_creators(text, text, integer) TO authenticated, anon;

-- 11. Stories Tray, View Tracking, Insights & Close Friends RPCs
CREATE OR REPLACE FUNCTION public.get_story_feed_trays()
RETURNS TABLE (
  user_id uuid,
  username text,
  avatar_url text,
  stories_count integer,
  has_unseen boolean,
  has_close_friend_story boolean,
  latest_story_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
BEGIN
  RETURN QUERY
  SELECT
    us.user_id,
    COALESCE(pr.username, 'user') AS username,
    COALESCE(pr.avatar_url, '') AS avatar_url,
    count(us.id)::integer AS stories_count,
    CASE
      WHEN v_me IS NULL THEN true
      ELSE BOOL_OR(NOT EXISTS (
        SELECT 1 FROM public.story_views sv
        WHERE sv.story_id = us.id AND sv.viewer_id = v_me
      ))
    END AS has_unseen,
    BOOL_OR(us.visibility = 'close_friends') AS has_close_friend_story,
    max(us.created_at) AS latest_story_at
  FROM public.user_stories us
  JOIN public.profiles pr ON pr.id = us.user_id
  WHERE us.deleted_at IS NULL
    AND us.expires_at > now()
    AND COALESCE(pr.is_banned, false) = false
    AND COALESCE(pr.account_status, 'active') = 'active'
    AND (
      v_me = us.user_id
      OR (
        (v_me IS NULL OR (
          NOT public.is_blocked_between(v_me, us.user_id)
          AND NOT EXISTS (
            SELECT 1 FROM public.story_mutes sm
            WHERE sm.user_id = v_me AND sm.muted_user_id = us.user_id
          )
          AND NOT EXISTS (
            SELECT 1 FROM public.user_mutes um
            WHERE um.muter_id = v_me AND um.muted_id = us.user_id AND COALESCE(um.mute_stories, true) = true
          )
        ))
        AND (
          (
            COALESCE(us.visibility, 'public') <> 'close_friends'
            AND (
              COALESCE(pr.is_private, false) = false
              OR (v_me IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = us.user_id
              ))
            )
          )
          OR (
            us.visibility = 'close_friends'
            AND v_me IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM public.close_friends cf WHERE cf.user_id = us.user_id AND cf.friend_id = v_me
            )
          )
        )
      )
    )
  GROUP BY us.user_id, pr.username, pr.avatar_url
  ORDER BY
    (CASE WHEN v_me IS NOT NULL AND us.user_id = v_me THEN 1 ELSE 0 END) DESC,
    has_unseen DESC,
    latest_story_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_story_feed_trays() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_story_feed_trays() TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.record_story_view(p_story_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_story record;
  v_owner_private boolean := false;
BEGIN
  IF v_me IS NULL OR p_story_id IS NULL THEN
    RETURN;
  END IF;

  SELECT us.id, us.user_id, us.visibility, COALESCE(pr.is_private, false) AS is_private,
         COALESCE(pr.is_banned, false) AS is_banned, COALESCE(pr.account_status, 'active') AS account_status
  INTO v_story
  FROM public.user_stories us
  JOIN public.profiles pr ON pr.id = us.user_id
  WHERE us.id = p_story_id
    AND us.deleted_at IS NULL
    AND us.expires_at > now();

  IF v_story.id IS NULL OR v_story.is_banned OR v_story.account_status <> 'active' THEN
    RETURN;
  END IF;

  IF v_me <> v_story.user_id THEN
    IF public.is_blocked_between(v_me, v_story.user_id) THEN
      RETURN;
    END IF;
    IF v_story.visibility = 'close_friends' THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.close_friends cf WHERE cf.user_id = v_story.user_id AND cf.friend_id = v_me
      ) THEN
        RETURN;
      END IF;
    ELSIF v_story.is_private THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = v_story.user_id
      ) THEN
        RETURN;
      END IF;
    END IF;
  END IF;

  INSERT INTO public.story_views (story_id, viewer_id)
  VALUES (p_story_id, v_me)
  ON CONFLICT (story_id, viewer_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.record_story_view(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_story_view(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_story_insights_and_viewers(p_story_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_story record;
  v_viewers jsonb := '[]'::jsonb;
  v_reactions jsonb := '[]'::jsonb;
  v_replies jsonb := '[]'::jsonb;
BEGIN
  IF v_me IS NULL OR p_story_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT us.id, us.user_id, us.views_count, us.likes_count, us.replies_count
  INTO v_story
  FROM public.user_stories us
  WHERE us.id = p_story_id AND us.deleted_at IS NULL;

  IF v_story.id IS NULL THEN
    RETURN jsonb_build_object(
      'views_count', 0,
      'likes_count', 0,
      'replies_count', 0,
      'viewers', '[]'::jsonb,
      'reactions', '[]'::jsonb,
      'replies', '[]'::jsonb
    );
  END IF;

  IF v_story.user_id <> v_me THEN
    RAISE EXCEPTION 'Forbidden: only the story owner can inspect viewers';
  END IF;

  SELECT COALESCE(jsonb_agg(vobj ORDER BY viewed_at DESC), '[]'::jsonb)
  INTO v_viewers
  FROM (
    SELECT
      sv.viewed_at,
      jsonb_build_object(
        'viewer_id', sv.viewer_id,
        'username', COALESCE(pr.username, 'user'),
        'full_name', trim(COALESCE(pr.first_name, '') || ' ' || COALESCE(pr.last_name, '')),
        'avatar_url', COALESCE(pr.avatar_url, ''),
        'is_verified', COALESCE(pr.is_verified, false),
        'viewed_at', sv.viewed_at,
        'has_liked', EXISTS (
          SELECT 1 FROM public.story_likes sl WHERE sl.story_id = p_story_id AND sl.user_id = sv.viewer_id
        ),
        'reaction_emoji', (
          SELECT sr.emoji FROM public.story_reactions sr WHERE sr.story_id = p_story_id AND sr.user_id = sv.viewer_id LIMIT 1
        )
      ) AS vobj
    FROM public.story_views sv
    JOIN public.profiles pr ON pr.id = sv.viewer_id
    WHERE sv.story_id = p_story_id
    ORDER BY sv.viewed_at DESC
    LIMIT 100
  ) vs;

  SELECT COALESCE(jsonb_agg(rxobj ORDER BY created_at DESC), '[]'::jsonb)
  INTO v_reactions
  FROM (
    SELECT
      sr.created_at,
      jsonb_build_object(
        'id', sr.id,
        'user_id', sr.user_id,
        'username', COALESCE(pr.username, 'user'),
        'full_name', trim(COALESCE(pr.first_name, '') || ' ' || COALESCE(pr.last_name, '')),
        'avatar_url', COALESCE(pr.avatar_url, ''),
        'is_verified', COALESCE(pr.is_verified, false),
        'emoji', sr.emoji,
        'created_at', sr.created_at
      ) AS rxobj
    FROM public.story_reactions sr
    JOIN public.profiles pr ON pr.id = sr.user_id
    WHERE sr.story_id = p_story_id
    ORDER BY sr.created_at DESC
    LIMIT 100
  ) rxs;

  SELECT COALESCE(jsonb_agg(robj ORDER BY created_at DESC), '[]'::jsonb)
  INTO v_replies
  FROM (
    SELECT
      srep.created_at,
      jsonb_build_object(
        'id', srep.id,
        'sender_id', srep.sender_id,
        'username', COALESCE(pr.username, 'user'),
        'full_name', trim(COALESCE(pr.first_name, '') || ' ' || COALESCE(pr.last_name, '')),
        'avatar_url', COALESCE(pr.avatar_url, ''),
        'reply_text', srep.reply_text,
        'created_at', srep.created_at
      ) AS robj
    FROM public.story_replies srep
    JOIN public.profiles pr ON pr.id = srep.sender_id
    WHERE srep.story_id = p_story_id
    ORDER BY srep.created_at DESC
    LIMIT 100
  ) rs;

  RETURN jsonb_build_object(
    'views_count', GREATEST(COALESCE(v_story.views_count, 0), jsonb_array_length(v_viewers)),
    'likes_count', COALESCE(v_story.likes_count, 0),
    'replies_count', GREATEST(COALESCE(v_story.replies_count, 0), jsonb_array_length(v_replies)),
    'viewers', v_viewers,
    'reactions', v_reactions,
    'replies', v_replies
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_story_insights_and_viewers(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_story_insights_and_viewers(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.toggle_close_friend(p_friend_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_exists boolean := false;
BEGIN
  IF v_me IS NULL OR p_friend_id IS NULL OR p_friend_id = v_me THEN
    RAISE EXCEPTION 'Invalid close friend target';
  END IF;

  IF public.is_blocked_between(v_me, p_friend_id) THEN
    RAISE EXCEPTION 'Cannot add blocked user to close friends';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.close_friends cf
    WHERE cf.user_id = v_me AND cf.friend_id = p_friend_id
  ) INTO v_exists;

  IF v_exists THEN
    DELETE FROM public.close_friends
    WHERE user_id = v_me AND friend_id = p_friend_id;
    RETURN jsonb_build_object('is_close_friend', false);
  ELSE
    INSERT INTO public.close_friends (user_id, friend_id)
    VALUES (v_me, p_friend_id)
    ON CONFLICT (user_id, friend_id) DO NOTHING;
    RETURN jsonb_build_object('is_close_friend', true);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.toggle_close_friend(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.toggle_close_friend(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_close_friends_profiles(
  p_query text DEFAULT ''
)
RETURNS TABLE (
  id uuid,
  username text,
  first_name text,
  last_name text,
  avatar_url text,
  is_verified boolean,
  is_close_friend boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_raw_q text := trim(coalesce(p_query, ''));
  v_esc_q text := replace(replace(replace(v_raw_q, '\', '\\'), '%', '\%'), '_', '\_');
BEGIN
  IF v_me IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    pr.id,
    COALESCE(pr.username, 'user') AS username,
    COALESCE(pr.first_name, '') AS first_name,
    COALESCE(pr.last_name, '') AS last_name,
    COALESCE(pr.avatar_url, '') AS avatar_url,
    COALESCE(pr.is_verified, false) AS is_verified,
    EXISTS (
      SELECT 1 FROM public.close_friends cf WHERE cf.user_id = v_me AND cf.friend_id = pr.id
    ) AS is_close_friend
  FROM public.profiles pr
  WHERE pr.id <> v_me
    AND COALESCE(pr.is_banned, false) = false
    AND COALESCE(pr.account_status, 'active') = 'active'
    AND NOT public.is_blocked_between(v_me, pr.id)
    AND (
      EXISTS (SELECT 1 FROM public.close_friends cf WHERE cf.user_id = v_me AND cf.friend_id = pr.id)
      OR EXISTS (SELECT 1 FROM public.user_follows uf WHERE uf.follower_id = v_me AND uf.following_id = pr.id)
      OR EXISTS (SELECT 1 FROM public.user_follows uf2 WHERE uf2.follower_id = pr.id AND uf2.following_id = v_me)
      OR v_raw_q <> ''
    )
    AND (
      v_raw_q = ''
      OR COALESCE(pr.username, '') ILIKE ('%' || v_esc_q || '%') ESCAPE '\'
      OR COALESCE(pr.first_name, '') ILIKE ('%' || v_esc_q || '%') ESCAPE '\'
      OR COALESCE(pr.last_name, '') ILIKE ('%' || v_esc_q || '%') ESCAPE '\'
    )
  ORDER BY is_close_friend DESC, pr.username ASC
  LIMIT 60;
END;
$$;

REVOKE ALL ON FUNCTION public.get_close_friends_profiles(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_close_friends_profiles(text) TO authenticated;

COMMIT;
