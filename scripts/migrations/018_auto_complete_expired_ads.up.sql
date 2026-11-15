-- 018_auto_complete_expired_ads.up.sql
-- Production Ad Expiration Engine:
-- Automatically transitions ad campaigns whose ends_at has elapsed or whose budget is exhausted
-- from 'active' / 'pending_review' / 'paused' to 'completed'.
-- Includes:
-- 1. Autonomous sweep function public.auto_complete_expired_ad_campaigns()
-- 2. Pre-write trigger on ad_campaigns
-- 3. Self-healing invocation on get_my_advertiser_dashboard() & serve_eligible_ad()
-- 4. Scheduled background execution via pg_cron (if available)

-- 1. Core Sweep & Expiration Function
CREATE OR REPLACE FUNCTION public.auto_complete_expired_ad_campaigns()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_affected integer := 0;
BEGIN
  UPDATE public.ad_campaigns
  SET
    status = 'completed',
    updated_at = now()
  WHERE status IN ('active', 'pending_review', 'paused', 'draft')
    AND (
      (ends_at IS NOT NULL AND ends_at <= now())
      OR (total_budget > 0 AND spent_amount >= total_budget)
    );

  GET DIAGNOSTICS v_affected = ROW_COUNT;
  RETURN v_affected;
END;
$$;

GRANT EXECUTE ON FUNCTION public.auto_complete_expired_ad_campaigns() TO authenticated, service_role, anon;

-- 2. Trigger Function on ad_campaigns to guarantee no expired row can be saved as active
CREATE OR REPLACE FUNCTION public.check_ad_campaign_expiry_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('active', 'pending_review', 'paused', 'draft') THEN
    IF (NEW.ends_at IS NOT NULL AND NEW.ends_at <= now())
       OR (NEW.total_budget > 0 AND NEW.spent_amount >= NEW.total_budget) THEN
      NEW.status := 'completed';
      NEW.updated_at := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_check_ad_campaign_expiry ON public.ad_campaigns;
CREATE TRIGGER tr_check_ad_campaign_expiry
  BEFORE INSERT OR UPDATE ON public.ad_campaigns
  FOR EACH ROW
  EXECUTE FUNCTION public.check_ad_campaign_expiry_trigger();

-- 3. Harden protect_ad_campaign_columns so 'completed' status is universally permitted upon expiry
CREATE OR REPLACE FUNCTION public.protect_ad_campaign_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
     OR COALESCE(auth.role(), '') = 'service_role'
     OR public.is_app_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status NOT IN ('draft', 'pending_review', 'completed')
       OR COALESCE(NEW.spent_amount, 0) <> 0
       OR COALESCE(NEW.spent_today, 0) <> 0
       OR COALESCE(NEW.impressions_count, 0) <> 0
       OR COALESCE(NEW.clicks_count, 0) <> 0
       OR COALESCE(NEW.conversions_count, 0) <> 0
       OR NEW.approved_at IS NOT NULL THEN
      RAISE EXCEPTION 'Insufficient privileges to bypass ad campaign review or initialize spend counters'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- Allow completion if expired or budget exhausted
  IF NEW.status = 'completed' AND (
    (OLD.ends_at IS NOT NULL AND OLD.ends_at <= now())
    OR (OLD.total_budget > 0 AND OLD.spent_amount >= OLD.total_budget)
  ) THEN
    RETURN NEW;
  END IF;

  IF NEW.advertiser_id IS DISTINCT FROM OLD.advertiser_id
     OR NEW.spent_amount IS DISTINCT FROM OLD.spent_amount
     OR NEW.spent_today IS DISTINCT FROM OLD.spent_today
     OR NEW.spent_today_date IS DISTINCT FROM OLD.spent_today_date
     OR NEW.impressions_count IS DISTINCT FROM OLD.impressions_count
     OR NEW.clicks_count IS DISTINCT FROM OLD.clicks_count
     OR NEW.conversions_count IS DISTINCT FROM OLD.conversions_count
     OR NEW.approved_at IS DISTINCT FROM OLD.approved_at
     OR NEW.rejection_reason IS DISTINCT FROM OLD.rejection_reason
     OR (NEW.status IS DISTINCT FROM OLD.status AND NEW.status NOT IN ('draft', 'pending_review', 'paused', 'completed')) THEN
    RAISE EXCEPTION 'Insufficient privileges to modify protected ad campaign financial or approval fields'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

-- 4. Self-Healing get_my_advertiser_dashboard(): Sweeps before read & reports realtime completed status
CREATE OR REPLACE FUNCTION public.get_my_advertiser_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_adv public.advertisers%ROWTYPE;
  v_campaigns jsonb := '[]'::jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_totals jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  -- Auto-complete any expired campaigns before building the dashboard
  PERFORM public.auto_complete_expired_ad_campaigns();

  SELECT * INTO v_adv FROM public.advertisers WHERE user_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'advertiser', NULL,
      'campaigns', '[]'::jsonb,
      'invoices', '[]'::jsonb,
      'totals', jsonb_build_object(
        'impressions', 0, 'clicks', 0, 'conversions', 0, 'spent', 0, 'ctr', 0
      )
    );
  END IF;

  SELECT COALESCE(jsonb_agg(row_json ORDER BY created_at DESC), '[]'::jsonb)
  INTO v_campaigns
  FROM (
    SELECT
      c.created_at,
      jsonb_build_object(
        'id', c.id,
        'source_post_id', c.source_post_id,
        'name', c.name,
        'objective', c.objective,
        'placement', c.placement,
        'status', CASE
          WHEN (c.ends_at IS NOT NULL AND c.ends_at <= now()) OR (c.total_budget > 0 AND c.spent_amount >= c.total_budget) THEN 'completed'
          ELSE c.status
        END,
        'pricing_model', c.pricing_model,
        'bid_amount', c.bid_amount,
        'daily_budget', c.daily_budget,
        'total_budget', c.total_budget,
        'spent_amount', c.spent_amount,
        'spent_today', CASE WHEN c.spent_today_date = CURRENT_DATE THEN c.spent_today ELSE 0 END,
        'impressions_count', c.impressions_count,
        'clicks_count', c.clicks_count,
        'conversions_count', c.conversions_count,
        'ctr', CASE WHEN c.impressions_count > 0 THEN ROUND((c.clicks_count::numeric / c.impressions_count::numeric) * 100.0, 2) ELSE 0 END,
        'daily_frequency_cap', c.daily_frequency_cap,
        'min_cooldown_seconds', c.min_cooldown_seconds,
        'starts_at', c.starts_at,
        'ends_at', c.ends_at,
        'approved_at', c.approved_at,
        'rejection_reason', c.rejection_reason,
        'created_at', c.created_at,
        'creative', (
          SELECT jsonb_build_object(
            'id', cr.id, 'title', cr.title, 'body', cr.body,
            'media_url', cr.media_url, 'media_type', cr.media_type,
            'cta_label', cr.cta_label, 'destination_url', cr.destination_url,
            'status', cr.status
          )
          FROM public.ad_creatives cr
          WHERE cr.campaign_id = c.id
          ORDER BY cr.created_at DESC
          LIMIT 1
        ),
        'targeting', (
          SELECT jsonb_build_object(
            'countries', t.countries, 'languages', t.languages,
            'interests', t.interests, 'min_age', t.min_age,
            'max_age', t.max_age, 'gender', t.gender
          )
          FROM public.ad_targeting t
          WHERE t.campaign_id = c.id
          LIMIT 1
        )
      ) AS row_json
    FROM public.ad_campaigns c
    WHERE c.advertiser_id = v_adv.id
  ) sub;

  SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.created_at DESC), '[]'::jsonb)
  INTO v_invoices
  FROM public.ad_invoices i
  WHERE i.advertiser_id = v_adv.id;

  SELECT jsonb_build_object(
    'impressions', COALESCE(SUM(impressions_count), 0),
    'clicks', COALESCE(SUM(clicks_count), 0),
    'conversions', COALESCE(SUM(conversions_count), 0),
    'spent', ROUND(COALESCE(SUM(spent_amount), 0), 2),
    'ctr', CASE WHEN COALESCE(SUM(impressions_count), 0) > 0
      THEN ROUND((COALESCE(SUM(clicks_count), 0)::numeric / SUM(impressions_count)::numeric) * 100.0, 2)
      ELSE 0 END
  )
  INTO v_totals
  FROM public.ad_campaigns
  WHERE advertiser_id = v_adv.id;

  RETURN jsonb_build_object(
    'ok', true,
    'advertiser', to_jsonb(v_adv),
    'campaigns', v_campaigns,
    'invoices', v_invoices,
    'totals', v_totals
  );
END;
$$;

-- 5. Self-Healing serve_eligible_ad(): Sweeps expired before selecting candidate
CREATE OR REPLACE FUNCTION public.serve_eligible_ad(
  p_placement text DEFAULT 'feed',
  p_user_id uuid DEFAULT NULL,
  p_country text DEFAULT NULL,
  p_interest text DEFAULT NULL,
  p_exclude_campaign_ids uuid[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_placement text := lower(trim(COALESCE(p_placement, 'feed')));
  v_uid uuid;
  v_country text := NULLIF(trim(COALESCE(p_country, '')), '');
  v_interest text := NULLIF(trim(COALESCE(p_interest, '')), '');
  v_rec record;
BEGIN
  IF v_placement NOT IN ('feed', 'story', 'reel', 'explore') THEN
    v_placement := 'feed';
  END IF;

  -- Auto-complete expired campaigns
  PERFORM public.auto_complete_expired_ad_campaigns();

  IF current_user IN ('postgres', 'supabase_admin', 'supabase_auth_admin', 'service_role')
     OR COALESCE(auth.role(), '') = 'service_role' THEN
    v_uid := COALESCE(p_user_id, auth.uid());
  ELSE
    v_uid := auth.uid();
  END IF;

  IF v_uid IS NOT NULL AND v_country IS NULL THEN
    SELECT NULLIF(trim(country), '') INTO v_country
    FROM public.profiles
    WHERE id = v_uid;
  END IF;

  SELECT
    c.id AS campaign_id,
    c.source_post_id,
    c.name AS campaign_name,
    c.objective,
    c.placement AS campaign_placement,
    c.pricing_model,
    c.bid_amount,
    c.daily_frequency_cap,
    c.min_cooldown_seconds,
    cr.id AS creative_id,
    cr.title,
    cr.body,
    cr.media_url,
    cr.media_type,
    cr.cta_label,
    cr.destination_url,
    adv.id AS advertiser_id,
    adv.business_name
  INTO v_rec
  FROM public.ad_campaigns c
  JOIN public.advertisers adv ON adv.id = c.advertiser_id
  JOIN public.ad_creatives cr ON cr.campaign_id = c.id
  LEFT JOIN public.ad_targeting t ON t.campaign_id = c.id
  WHERE adv.status = 'approved'
    AND adv.balance > 0
    AND c.status = 'active'
    AND c.approved_at IS NOT NULL
    AND cr.status = 'approved'
    AND (c.placement = v_placement OR c.placement = 'all')
    AND c.starts_at <= now()
    AND (c.ends_at IS NULL OR c.ends_at > now())
    AND c.spent_amount < c.total_budget
    AND (
      CASE WHEN c.spent_today_date = CURRENT_DATE THEN c.spent_today ELSE 0 END
    ) < c.daily_budget
    AND (
      p_exclude_campaign_ids IS NULL
      OR cardinality(p_exclude_campaign_ids) = 0
      OR NOT (c.id = ANY (p_exclude_campaign_ids))
    )
    AND (
      t.id IS NULL
      OR cardinality(t.countries) = 0
      OR (v_country IS NOT NULL AND lower(v_country) = ANY (SELECT lower(x) FROM unnest(t.countries) AS x))
    )
    AND (
      t.id IS NULL
      OR cardinality(t.interests) = 0
      OR (v_interest IS NOT NULL AND lower(v_interest) = ANY (SELECT lower(x) FROM unnest(t.interests) AS x))
    )
    AND (
      v_uid IS NULL
      OR NOT EXISTS (
        SELECT 1 FROM public.ad_frequency_caps fc
        WHERE fc.campaign_id = c.id
          AND fc.user_id = v_uid
          AND fc.window_date = CURRENT_DATE
          AND (
            fc.impressions_today >= c.daily_frequency_cap
            OR (
              c.min_cooldown_seconds > 0
              AND fc.last_shown_at > now() - make_interval(secs => c.min_cooldown_seconds)
            )
          )
      )
    )
  ORDER BY
    (adv.user_id = v_uid) ASC NULLS LAST,
    (c.spent_amount / GREATEST(c.total_budget, 1)) ASC,
    random()
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'ad', NULL);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'ad', jsonb_build_object(
      'campaign_id', v_rec.campaign_id,
      'creative_id', v_rec.creative_id,
      'source_post_id', v_rec.source_post_id,
      'advertiser_id', v_rec.advertiser_id,
      'business_name', v_rec.business_name,
      'campaign_name', v_rec.campaign_name,
      'objective', v_rec.objective,
      'placement', v_placement,
      'pricing_model', v_rec.pricing_model,
      'title', v_rec.title,
      'body', v_rec.body,
      'media_url', v_rec.media_url,
      'media_type', v_rec.media_type,
      'cta_label', v_rec.cta_label,
      'destination_url', v_rec.destination_url
    )
  );
END;
$$;

-- 6. Setup pg_cron periodic job if pg_cron extension is installed
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'auto_complete_expired_ads';
    PERFORM cron.schedule(
      'auto_complete_expired_ads',
      '*/5 * * * *',
      'SELECT public.auto_complete_expired_ad_campaigns();'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- 7. Execute immediately to mark all currently expired campaigns as completed
SELECT public.auto_complete_expired_ad_campaigns();

