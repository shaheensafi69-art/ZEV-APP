-- 023_ultra_data_saver_cloud_drive_communities_2fa.down.sql
BEGIN;

DROP FUNCTION IF EXISTS public.terminate_all_other_sessions(text);
DROP FUNCTION IF EXISTS public.terminate_user_session(uuid);
DROP FUNCTION IF EXISTS public.disable_two_factor(text);
DROP FUNCTION IF EXISTS public.verify_two_factor_pin(text);
DROP FUNCTION IF EXISTS public.setup_two_factor_pin(text);
DROP TABLE IF EXISTS public.user_two_factor_auth CASCADE;

DROP FUNCTION IF EXISTS public.mark_best_community_answer(uuid, uuid);
DROP FUNCTION IF EXISTS public.vote_community_post(uuid, smallint);
DROP TRIGGER IF EXISTS trg_comm_comments_count ON public.community_comments;
DROP TRIGGER IF EXISTS trg_comm_posts_count ON public.community_posts;
DROP TRIGGER IF EXISTS trg_comm_members_count ON public.community_members;
DROP FUNCTION IF EXISTS public.trg_community_counts_func();
DROP TABLE IF EXISTS public.community_comment_votes CASCADE;
DROP TABLE IF EXISTS public.community_comments CASCADE;
DROP TABLE IF EXISTS public.community_post_votes CASCADE;
DROP TABLE IF EXISTS public.community_posts CASCADE;
DROP TABLE IF EXISTS public.community_members CASCADE;
DROP TABLE IF EXISTS public.communities CASCADE;

DROP FUNCTION IF EXISTS public.get_reel_retention_analytics(uuid);
DROP FUNCTION IF EXISTS public.get_audience_peak_hours(uuid);
DROP INDEX IF EXISTS idx_reels_scheduled_and_drafts;
ALTER TABLE public.reels DROP COLUMN IF EXISTS is_draft;
ALTER TABLE public.reels DROP COLUMN IF EXISTS scheduled_at;

DROP FUNCTION IF EXISTS public.get_user_cloud_stats();
DROP TRIGGER IF EXISTS trg_cloud_items_count ON public.user_cloud_items;
DROP FUNCTION IF EXISTS public.trg_cloud_items_count_func();
DROP TABLE IF EXISTS public.user_cloud_items CASCADE;
DROP TABLE IF EXISTS public.user_cloud_folders CASCADE;

ALTER TABLE public.user_settings DROP COLUMN IF EXISTS image_compression_level;
ALTER TABLE public.user_settings DROP COLUMN IF EXISTS video_quality_preference;
ALTER TABLE public.user_settings DROP COLUMN IF EXISTS auto_download_media;
ALTER TABLE public.user_settings DROP COLUMN IF EXISTS data_saver_mode;

COMMIT;
