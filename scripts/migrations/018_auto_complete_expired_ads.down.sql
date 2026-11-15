-- 018_auto_complete_expired_ads.down.sql
DROP TRIGGER IF EXISTS tr_check_ad_campaign_expiry ON public.ad_campaigns;
DROP FUNCTION IF EXISTS public.check_ad_campaign_expiry_trigger();
DROP FUNCTION IF EXISTS public.auto_complete_expired_ad_campaigns();

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'auto_complete_expired_ads';
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
