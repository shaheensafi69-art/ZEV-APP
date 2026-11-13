-- 014_ads_boost_and_hybrid_polish.down.sql
DROP INDEX IF EXISTS public.idx_ad_campaigns_source_post;
ALTER TABLE public.ad_campaigns DROP COLUMN IF EXISTS source_post_id;
