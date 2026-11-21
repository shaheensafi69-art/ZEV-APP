-- 021_atomic_counters_and_recommendation_engine.down.sql
-- Revert migration 021

BEGIN;

DROP TABLE IF EXISTS public.user_content_interactions CASCADE;

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS profile_views_count;

ALTER TABLE public.reel_views
  DROP COLUMN IF EXISTS watch_time_ms;

COMMIT;
