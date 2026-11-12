-- 004_core_schema_expansion_indexes.down.sql
DROP INDEX IF EXISTS public.idx_profiles_referral_count_desc;
DROP INDEX IF EXISTS public.idx_profiles_search_gin;
DROP INDEX IF EXISTS public.idx_direct_messages_conv_created;
DROP INDEX IF EXISTS public.idx_reels_author_created;
DROP INDEX IF EXISTS public.idx_reels_published_cursor;
DROP INDEX IF EXISTS public.idx_post_reposts_post;
DROP INDEX IF EXISTS public.idx_discussion_bookmarks_user_created;
DROP INDEX IF EXISTS public.idx_discussion_likes_post;
DROP INDEX IF EXISTS public.idx_discussion_posts_search_gin;
DROP INDEX IF EXISTS public.idx_discussion_posts_author_created;
DROP INDEX IF EXISTS public.idx_discussion_posts_feed_cursor;

DROP TABLE IF EXISTS public.live_viewers;
DROP TABLE IF EXISTS public.live_reactions;
DROP TABLE IF EXISTS public.live_comments;
DROP TABLE IF EXISTS public.live_streams;

DROP TABLE IF EXISTS public.ad_invoices;
DROP TABLE IF EXISTS public.ad_frequency_caps;
DROP TABLE IF EXISTS public.ad_conversions;
DROP TABLE IF EXISTS public.ad_clicks;
DROP TABLE IF EXISTS public.ad_impressions;
DROP TABLE IF EXISTS public.ad_targeting;
DROP TABLE IF EXISTS public.ad_creatives;
DROP TABLE IF EXISTS public.ad_campaigns;
DROP TABLE IF EXISTS public.advertisers;

DROP TABLE IF EXISTS public.message_requests;
DROP TABLE IF EXISTS public.conversation_mutes;
DROP TABLE IF EXISTS public.conversation_pins;
DROP TABLE IF EXISTS public.message_edits;
DROP TABLE IF EXISTS public.message_deletions;
DROP TABLE IF EXISTS public.message_reads;
DROP TABLE IF EXISTS public.message_deliveries;

DROP TRIGGER IF EXISTS trg_direct_message_update_conversation ON public.direct_messages;
DROP TRIGGER IF EXISTS trg_direct_message_attach_conversation ON public.direct_messages;
DROP FUNCTION IF EXISTS public.trg_direct_message_update_conversation();
DROP FUNCTION IF EXISTS public.trg_direct_message_attach_conversation();
DROP FUNCTION IF EXISTS public.get_or_create_direct_conversation(uuid);

DROP POLICY IF EXISTS reels_select ON public.reels;
CREATE POLICY reels_select ON public.reels FOR SELECT TO anon, authenticated USING (COALESCE(is_published, true) = true OR auth.uid() = user_id);
DROP POLICY IF EXISTS discussion_posts_select_visible ON public.discussion_posts;
CREATE POLICY "Allow public read access for discussion_posts" ON public.discussion_posts FOR SELECT TO public USING (true);
DROP POLICY IF EXISTS user_stories_select_visible ON public.user_stories;
CREATE POLICY "Stories Select Policy" ON public.user_stories FOR SELECT TO public USING (expires_at > now());

DROP POLICY IF EXISTS direct_messages_select_participant ON public.direct_messages;
DROP POLICY IF EXISTS direct_messages_insert_participant ON public.direct_messages;
DROP POLICY IF EXISTS direct_messages_update_participant ON public.direct_messages;

ALTER TABLE public.direct_messages DROP CONSTRAINT IF EXISTS direct_messages_conversation_id_fkey;
DROP TABLE IF EXISTS public.conversation_members;
DROP TABLE IF EXISTS public.conversations;
DROP FUNCTION IF EXISTS public.is_conversation_admin(uuid, uuid);
DROP FUNCTION IF EXISTS public.is_conversation_member(uuid, uuid);

DROP TABLE IF EXISTS public.appeals;
DROP TABLE IF EXISTS public.trending_topics;
DROP TABLE IF EXISTS public.search_history;
DROP TABLE IF EXISTS public.story_mutes;
DROP TABLE IF EXISTS public.story_replies;
DROP TABLE IF EXISTS public.story_reactions;
DROP TABLE IF EXISTS public.media_deletion_queue;
DROP TABLE IF EXISTS public.hidden_posts;
DROP TABLE IF EXISTS public.post_reports;
DROP TABLE IF EXISTS public.post_views;
DROP TABLE IF EXISTS public.comment_pins;
DROP TABLE IF EXISTS public.comment_likes;
DROP TABLE IF EXISTS public.post_media;
DROP TABLE IF EXISTS public.user_mutes;
DROP TABLE IF EXISTS public.close_friends;
DROP TABLE IF EXISTS public.follow_requests;
DROP TABLE IF EXISTS public.notification_deliveries;
DROP TABLE IF EXISTS public.notification_preferences;
DROP TABLE IF EXISTS public.account_deletions;
DROP TABLE IF EXISTS public.user_links;
DROP TABLE IF EXISTS public.user_security_logs;
DROP TABLE IF EXISTS public.user_sessions;
DROP TABLE IF EXISTS public.user_preferences;
DROP TABLE IF EXISTS public.user_privacy_settings;
DROP TABLE IF EXISTS public.user_settings;

ALTER TABLE public.direct_messages
  DROP COLUMN IF EXISTS mime_type,
  DROP COLUMN IF EXISTS file_size,
  DROP COLUMN IF EXISTS file_name,
  DROP COLUMN IF EXISTS deleted_for_user_ids,
  DROP COLUMN IF EXISTS deleted_at,
  DROP COLUMN IF EXISTS edited_at,
  DROP COLUMN IF EXISTS forwarded_from_id,
  DROP COLUMN IF EXISTS reply_to_message_id,
  DROP COLUMN IF EXISTS message_type,
  DROP COLUMN IF EXISTS conversation_id;

ALTER TABLE public.user_stories
  DROP COLUMN IF EXISTS deleted_at,
  DROP COLUMN IF EXISTS replies_count,
  DROP COLUMN IF EXISTS likes_count,
  DROP COLUMN IF EXISTS views_count,
  DROP COLUMN IF EXISTS visibility;

ALTER TABLE public.reels
  DROP COLUMN IF EXISTS audio_name,
  DROP COLUMN IF EXISTS edited_at,
  DROP COLUMN IF EXISTS deleted_at,
  DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS shares_count,
  DROP COLUMN IF EXISTS bookmarks_count,
  DROP COLUMN IF EXISTS comments_enabled,
  DROP COLUMN IF EXISTS visibility;

ALTER TABLE public.reel_comments
  DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS deleted_at,
  DROP COLUMN IF EXISTS edited_at,
  DROP COLUMN IF EXISTS is_pinned,
  DROP COLUMN IF EXISTS likes_count,
  DROP COLUMN IF EXISTS parent_comment_id;

ALTER TABLE public.discussion_comments
  DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS deleted_at,
  DROP COLUMN IF EXISTS edited_at,
  DROP COLUMN IF EXISTS is_pinned,
  DROP COLUMN IF EXISTS likes_count;

ALTER TABLE public.discussion_posts
  DROP COLUMN IF EXISTS tagged_user_ids,
  DROP COLUMN IF EXISTS collaborator_ids,
  DROP COLUMN IF EXISTS edited_at,
  DROP COLUMN IF EXISTS deleted_at,
  DROP COLUMN IF EXISTS updated_at,
  DROP COLUMN IF EXISTS published_at,
  DROP COLUMN IF EXISTS scheduled_at,
  DROP COLUMN IF EXISTS is_draft,
  DROP COLUMN IF EXISTS location,
  DROP COLUMN IF EXISTS views_count,
  DROP COLUMN IF EXISTS bookmarks_count,
  DROP COLUMN IF EXISTS reposts_count,
  DROP COLUMN IF EXISTS comments_count,
  DROP COLUMN IF EXISTS likes_count,
  DROP COLUMN IF EXISTS comments_enabled,
  DROP COLUMN IF EXISTS visibility,
  DROP COLUMN IF EXISTS post_type;

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS reels_count,
  DROP COLUMN IF EXISTS posts_count,
  DROP COLUMN IF EXISTS following_count,
  DROP COLUMN IF EXISTS followers_count,
  DROP COLUMN IF EXISTS username_changed_at,
  DROP COLUMN IF EXISTS location,
  DROP COLUMN IF EXISTS account_status,
  DROP COLUMN IF EXISTS ban_reason,
  DROP COLUMN IF EXISTS banned_until,
  DROP COLUMN IF EXISTS is_banned,
  DROP COLUMN IF EXISTS is_private;
